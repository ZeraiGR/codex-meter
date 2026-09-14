#!/usr/bin/env python3
"""Exercise the real CLI/transport against a local fake server; never reads Codex auth."""
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1]).resolve()
server = r'''
import json, pathlib, sys
root = pathlib.Path(__file__).parent
mode = (root / 'mode').read_text()
counter = root / 'attempts'
attempt = int(counter.read_text()) + 1 if counter.exists() else 1
counter.write_text(str(attempt))
for line in sys.stdin:
    request = json.loads(line)
    if 'id' not in request: continue
    method = request['method']
    result = {}
    error = None
    if method == 'account/read':
        result = {'account': {'type': 'chatgpt', 'planType': 'plus', 'email': 'test@example.invalid'}}
    if method == 'account/rateLimits/read':
        if mode == 'closed': sys.exit(0)
        if mode == 'permanent' or mode == 'auth' or (mode == 'transient' and attempt < 3):
            error = {'code': -32603, 'message': '401 Unauthorized' if mode == 'auth' else 'temporary upstream failure; Bearer test-secret'}
        else:
            result = {'rateLimits': {'limitId': 'codex', 'primary': {'usedPercent': 17, 'windowDurationMins': 10080, 'resetsAt': 2000000000}}}
    response = {'id': request['id']}
    response.update({'error': error} if error else {'result': result})
    print(json.dumps(response), flush=True)
'''

for mode, attempts in [('transient', 3), ('permanent', 3), ('auth', 1), ('closed', 3)]:
    with tempfile.TemporaryDirectory(prefix='codex-meter-rpc-') as directory:
        root = Path(directory)
        fake = root / 'fake-codex'
        fake.write_text('#!' + sys.executable + '\n' + server)
        fake.chmod(0o700)
        (root / 'mode').write_text(mode)
        env = dict(os.environ, CODEX_METER_HOME=str(root))
        subprocess.run([str(binary), 'status'], env=env, check=True, capture_output=True)
        old = '{"sentinel":"last-good-snapshot"}'
        with sqlite3.connect(root / 'meter.sqlite') as db:
            db.execute('INSERT INTO kv VALUES (?,?)', ('codexPath', str(fake)))
            db.execute('INSERT INTO kv VALUES (?,?)', ('snapshot', old))
        result = subprocess.run([str(binary), 'refresh'], env=env, capture_output=True, text=True, timeout=30)
        assert int((root / 'attempts').read_text()) == attempts, (mode, result.stderr)
        if mode == 'transient':
            assert result.returncode == 0, result.stderr
            assert json.loads(result.stdout)['buckets'][0]['primary']['usedPercent'] == 17
        else:
            assert result.returncode != 0, mode
            assert 'account/rateLimits/read' in result.stderr, result.stderr
            assert 'test-secret' not in result.stderr, result.stderr
            if mode == 'auth': assert 'войдите снова' in result.stderr
            with sqlite3.connect(root / 'meter.sqlite') as db:
                assert db.execute("SELECT value FROM kv WHERE key='snapshot'").fetchone()[0] == old
        print('PASS RPC ' + mode, flush=True)
