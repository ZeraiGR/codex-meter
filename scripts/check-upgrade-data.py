#!/usr/bin/env python3
"""Read and save a frozen schema-v1 fixture without automatic lifecycle changes."""
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
    rejected=subprocess.run([str(EXE),"task-end","--id","legacy-task"],env=env,capture_output=True)
    assert rejected.returncode!=0 and snapshot()==before,"Legacy agent command changed task state"
    rejected=subprocess.run([str(EXE),"task-pause","--id","legacy-task"],env=env,capture_output=True)
    assert rejected.returncode!=0
    after=snapshot()
    assert after==before,"Rejected lifecycle commands changed existing data"
    subprocess.run([str(EXE),"task-start","--thread","legacy-thread","--turn","legacy-run","--title","Review API"],env=env,check=True,stdout=subprocess.DEVNULL)
    after=snapshot()
    assert all(after[t]==before[t] for t in TABLES if t!="tasks"),"Saving a legacy task changed unrelated data"
    assert json.loads(after["tasks"][0][1])["status"]=="paused"
    print("PASS UPGRADE schema-v1 reads, totals, repeat-open, save and rejected lifecycle commands preserve existing data")
