---
name: codex-meter
description: Учитывать пользовательские задачи в Codex Meter, проверять бюджет перед типовой задачей и показывать историю расхода токенов, времени и квоты. Использовать при просьбе начать, продолжить, завершить учёт задачи или оценить доступный бюджет.
---

# Codex Meter

Use the installed local executable `~/Applications/Codex Meter.app/Contents/MacOS/codex-meter`. Its `--help` lists the supported commands. It reads the same local database as the menu bar app.

A task is a particular user outcome, not a session, assistant turn, or helper skill. Reuse its ID for clarifications, retries, and cross-session continuation. The UserPromptSubmit hook supplies the current thread/turn IDs and active task. If these IDs are absent, don't invent them; use the app to assign recorded turns later.

- `task-start --thread ID --turn ID --title 'specific outcome' --skill 'skill-name'` starts a task; Skills are execution metadata, never task types. Leave classification unassigned until explicitly identified by the user. Use `task-types` and `--type-id ID` to select an existing configured type; never invent a type or use `--kind` to classify. Use `--skill-version` if a version is known. Do not create a second task for nested skills or child agents.
- `forecast [--type-id ID] --model MODEL` returns local historical estimates and current quota freshness. Communicate `high` or `caution` risk before substantial work. `unknown` means insufficient evidence, not sufficient budget. Forecasts are advisory; do not add approval gates or change the user's requested model.
- Task statuses belong exclusively to the human using the app's task card or bulk status action. Never complete, pause, cancel, fail or reopen tasks yourself, even after delivering work, waiting for input, errors or switching tasks. `task-end` and `task-pause` are disabled starting with 1.4.14.
- `task-resume --id ID --thread ID --turn ID` in 1.4.14 or later binds tracking to the same outcome without changing any task's status or completion date. `task-start` reuses the current task with the same title without changing its status; creating a different task leaves the previous one unchanged. Hook binding continues even for closed tasks without reopening them.
- With older installed versions, use only `task-assign --id ID --thread ID --turn ID` to attach a run to an existing task. Do not use legacy `task-start`, `task-resume`, `task-pause` or `task-end`, which can change statuses automatically. Ask the human to update the app for safe cross-session tracking.
- `tasks`, `status`, and `forecast` are read-only. `refresh` requests subscription statistics from Codex services; it does not run a model. The app normally refreshes automatically.

Task quota and ruble values may be unknown or approximate. Preserve their quality labels. Parallel work allocated by tokens is a rough estimate, not a measured billing amount. Never substitute API prices for the user's subscription payment or interpret remaining quota percentage as a fixed token count. Tracking failures must not prevent the user's actual work.
