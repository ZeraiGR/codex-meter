#!/usr/bin/env python3
"""Read and modify a frozen schema-v1 fixture without losing unrelated rows."""
from pathlib import Path
import json
import os
import sqlite3
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]
EXE=ROOT/"dist/Codex Meter.app/Contents/MacOS/codex-meter"
TABLES=["tasks","turns","bindings","payments","observations","kv"]

with tempfile.TemporaryDirectory(prefix="meter-upgrade-data-") as temporary:
    db=Path(temporary)/"meter.sqlite"
    with sqlite3.connect(db) as con:con.executescript((ROOT/"Tests/fixtures/schema-v1.sql").read_text())
    def snapshot():
        with sqlite3.connect(db) as con:return {t:con.execute("SELECT * FROM "+t+" ORDER BY 1").fetchall() for t in TABLES}
    env=os.environ.copy();env["CODEX_METER_HOME"]=temporary
    before=snapshot()
    for _ in range(2):
        tasks=json.loads(subprocess.check_output([str(EXE),"tasks"],env=env,text=True))
        assert len(tasks)==1 and tasks[0]["id"]=="legacy-task" and tasks[0]["tokens"]==1100
        assert tasks[0]["seconds"]==120 and tasks[0]["status"]=="paused"
    assert snapshot()==before,"Opening the old database changed persisted rows"
    subprocess.run([str(EXE),"task-end","--id","legacy-task"],env=env,check=True,stdout=subprocess.DEVNULL)
    after=snapshot()
    assert all(after[t]==before[t] for t in TABLES if t!="tasks"),"Editing a legacy task changed unrelated data"
    assert json.loads(after["tasks"][0][1])["status"]=="completed"
    print("PASS UPGRADE schema-v1 reads, totals, repeat-open and edit preserve existing data")
