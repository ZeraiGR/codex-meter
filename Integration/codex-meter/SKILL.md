---
name: codex-meter
description: Учитывать пользовательские задачи в Codex Meter, проверять бюджет перед типовой задачей и показывать историю расхода токенов, времени и квоты. Использовать при просьбе начать, продолжить, завершить учёт задачи или оценить доступный бюджет.
---

# Codex Meter

Use the installed local executable `~/Applications/Codex Meter.app/Contents/MacOS/codex-meter`. Its `--help` lists the supported commands. It reads the same local database as the menu bar app.

A task is a particular user outcome, not a session, assistant turn, or helper skill. Reuse its ID for clarifications, retries, and cross-session continuation. The UserPromptSubmit hook supplies the current thread/turn IDs and active task. If these IDs are absent, don't invent them; use the app to assign recorded turns later.

- `task-start --thread ID --turn ID --title 'specific outcome' --kind 'repeatable-type'` starts a task; a skill's name is a useful type. Use `--skill-version` if a version is known. Do not create a second task for nested skills or child agents.
- `forecast --kind TYPE --model MODEL` returns local historical estimates and current quota freshness. Communicate `high` or `caution` risk before substantial work. `unknown` means insufficient evidence, not sufficient budget. Forecasts are advisory; do not add approval gates or change the user's requested model.
- `task-pause --id ID` records waiting for the user. `task-resume --id ID --thread ID --turn ID` resumes the same outcome.
- `task-end --id ID` marks the intended outcome delivered. Use `--outcome cancelled` or `failed` for those outcomes. A final assistant response alone is not proof that the user's task is complete.
- `tasks`, `status`, and `forecast` are read-only. `refresh` requests subscription statistics from Codex services; it does not run a model. The app normally refreshes automatically.

Task quota and ruble values may be unknown or approximate. Preserve their quality labels. Parallel work allocated by tokens is a rough estimate, not a measured billing amount. Never substitute API prices for the user's subscription payment or interpret remaining quota percentage as a fixed token count. Tracking failures must not prevent the user's actual work.
