# Codex Meter development

- Preserve user tasks, payments, run bindings and SQLite history. Tests must use isolated temporary data.
- Quota percentages are not fixed token allowances. Keep missing measurements and partial estimates explicit.
- Run `bash scripts/check-quality.sh` for behavior changes. Release changes must pass real update installation and rejection scenarios.
- Follow `docs/updates.md` for releases. Never commit signing keys, tokens, databases or raw journals.
- Update README and relevant guides when behavior changes. Screenshots must use synthetic data.
- On the owner's workstation, if a sibling `personal-docs` project exists, also follow its project documentation workflow and update the existing Codex Meter pages.

- Publishing a release does not authorize replacing the user's installed app. Leave installation to the user through the in-app updater unless they explicitly request installation.
