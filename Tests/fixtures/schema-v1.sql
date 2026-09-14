-- Synthetic schema-v1 fixture, verified readable by Codex Meter 1.3.2.
BEGIN TRANSACTION;
CREATE TABLE bindings (thread TEXT NOT NULL, turn TEXT NOT NULL, task_id TEXT NOT NULL, PRIMARY KEY(thread,turn));
INSERT INTO "bindings" VALUES('legacy-thread','legacy-run','legacy-task');
CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL);
INSERT INTO "kv" VALUES('active:legacy-thread','legacy-task');
CREATE TABLE observations (id INTEGER PRIMARY KEY, account TEXT NOT NULL, stamp REAL NOT NULL, data TEXT NOT NULL);
CREATE TABLE payments (id TEXT PRIMARY KEY, start REAL NOT NULL, end REAL NOT NULL, data TEXT NOT NULL);
INSERT INTO "payments" VALUES('legacy-payment',1704067200.0,1706745600.0,'{"id": "legacy-payment", "amount": 3000, "start": 725760000, "end": 728438400}');
CREATE TABLE tasks (id TEXT PRIMARY KEY, data TEXT NOT NULL);
INSERT INTO "tasks" VALUES('legacy-task','{"id": "legacy-task", "title": "Review API", "kind": "code-review", "status": "paused", "created": 725760000}');
CREATE TABLE turns (id TEXT PRIMARY KEY, thread TEXT NOT NULL, task_id TEXT, started REAL NOT NULL, data TEXT NOT NULL);
INSERT INTO "turns" VALUES('legacy-run','legacy-thread','legacy-task',1704067200.0,'{"id": "legacy-run", "thread": "legacy-thread", "started": 725760000, "ended": 725760120, "tokens": {"input": 1000, "cached": 800, "output": 100, "reasoning": 20}, "model": "fixture-model", "effort": "high", "title": "Review API", "outcome": "completed", "taskID": "legacy-task", "tokenEvents": []}');
CREATE INDEX turns_thread ON turns(thread);
CREATE INDEX observations_stamp ON observations(stamp);
COMMIT;
PRAGMA user_version=1;
