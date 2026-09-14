#!/usr/bin/env python3
"""Install the owned hook/skill, preserving all other Codex configuration."""
import argparse
import datetime
import json
import pathlib
import shutil
import sys

BEGIN = "# BEGIN CODEX METER (managed by codex-meter)"
END = "# END CODEX METER"

def install(codex_home, app, source):
    codex_home = pathlib.Path(codex_home)
    app = pathlib.Path(app).resolve()
    binary = app / "Contents/MacOS/codex-meter"
    if not binary.is_file():
        raise ValueError("Install Codex Meter.app before connecting it to Codex")
    config = codex_home / "config.toml"
    old = config.read_text() if config.exists() else ""
    target = codex_home / "skills/codex-meter"
    if target.exists() and not (target / ".codex-meter-owned").exists():
        raise ValueError("An unrelated codex-meter skill already exists; refusing to overwrite it")
    updated = old
    if BEGIN in updated:
        if END not in updated:
            raise ValueError("Incomplete Codex Meter configuration marker")
        before, rest = updated.split(BEGIN, 1)
        _, after = rest.split(END, 1)
        updated = before.rstrip() + "\n" + after.lstrip("\n")
    command = "'" + str(binary).replace("'", "'\"'\"'") + "' hook"
    block = "\n" + BEGIN + "\n[[hooks.UserPromptSubmit]]\n[[hooks.UserPromptSubmit.hooks]]\ntype = \"command\"\ncommand = " + json.dumps(command, ensure_ascii=False) + "\ntimeout = 5\n" + END + "\n"
    updated = updated.rstrip() + "\n" + block
    # Validate TOML where available (Python 3.11+).
    try:
        import tomllib
        tomllib.loads(updated)
    except ImportError:
        pass
    codex_home.mkdir(parents=True, exist_ok=True)
    if old != updated and config.exists():
        stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S-%f")
        shutil.copy2(config, codex_home / ("config.toml.before-codex-meter-" + stamp))
    target.mkdir(parents=True, exist_ok=True)
    shutil.copy2(pathlib.Path(source) / "SKILL.md", target / "SKILL.md")
    (target / ".codex-meter-owned").write_text("Codex Meter integration v1\n")
    temporary = config.with_name("config.toml.codex-meter-tmp")
    temporary.write_text(updated)
    temporary.chmod(0o600)
    temporary.replace(config)
    return str(target)

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--codex-home", default=str(pathlib.Path.home() / ".codex"))
    parser.add_argument("--app", default=str(pathlib.Path.home() / "Applications/Codex Meter.app"))
    parser.add_argument("--source", default=str(pathlib.Path(__file__).resolve().parent.parent / "Integration/codex-meter"))
    args = parser.parse_args()
    try:
        print(install(args.codex_home, args.app, args.source))
    except Exception as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
