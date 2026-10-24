# Codex Meter development

- Preserve user tasks, payments, run bindings and SQLite history. Tests must use isolated temporary data.
- Quota percentages are not fixed token allowances. Keep missing measurements and partial estimates explicit.
- Run `bash scripts/check-quality.sh` for behavior changes. Release changes must pass real update installation and rejection scenarios.
- Follow `docs/updates.md` for releases. Never commit signing keys, tokens, databases or raw journals.
- Update README and relevant guides when behavior changes. Screenshots must use synthetic data.
- On the owner's workstation, if a sibling `personal-docs` project exists, also follow its project documentation workflow and update the existing Codex Meter pages.

- Publishing a release does not authorize replacing the user's installed app. Leave installation to the user through the in-app updater unless they explicitly request installation.

## Обязательный полный выпуск на GitHub

Постоянное решение владельца от 2026-10-23: при обновлении Codex Meter доводить изменение до полноценного актуального релиза на GitHub. Это относится и к входящим в проект интеграциям, включая Telegram-бота. Локальная замена файлов или перезапуск службы не завершают поставку.

- Сохранять относящиеся к задаче исходники коммитами и отправлять их в GitHub; не включать чужие изменения без разбора.
- Повышать версию приложения и номер сборки, актуализировать release notes и выпускать соответствующий GitHub Release по `docs/updates.md`.
- Проходить все обязательные проверки. Проверять успешное завершение release workflow, опубликованные артефакты и appcast; один push или тег не считать выпуском.
- При блокере явно сообщать, что релиз не опубликован, что осталось сделать и какая версия доступна на GitHub. Не объявлять обновление полностью завершённым и не обходить проверки.
- Отдельно сообщать версии опубликованного релиза и установленного приложения. Установка на Mac по-прежнему требует явного поручения владельца.

Исключение допустимо, если пользователь явно ограничил задачу исследованием, черновиком или локальным экспериментом без выпуска.
