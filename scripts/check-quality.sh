#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/build-app.sh
task_native_arch=$(uname -m)
task_bin=".build/${task_native_arch}/${task_native_arch}-apple-macosx/release"
"$task_bin/meter-checks"
python3 scripts/check-rpc.py 'dist/Codex Meter.app/Contents/MacOS/codex-meter'
python3 scripts/check-upgrade-data.py
python3 -m unittest discover -s tests/release -v
CODEX_METER_UI_ARTIFACTS="${CODEX_METER_UI_ARTIFACTS:-$PWD/artifacts/ui}" 'dist/Codex Meter.app/Contents/MacOS/codex-meter' ui-check
python3 scripts/check-update-install.py
codesign --verify --deep --strict 'dist/Codex Meter.app'
python3 scripts/check-repository.py
