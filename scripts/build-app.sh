#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$task_root"
python3 scripts/fetch-sparkle.py
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-${TMPDIR:-/tmp}/codex-meter-clang-cache}"
export SWIFTPM_MODULECACHE_OVERRIDE="${SWIFTPM_MODULECACHE_OVERRIDE:-${TMPDIR:-/tmp}/codex-meter-module-cache}"
task_swift_args=(--disable-sandbox)
# CLT 27 beta ships SwiftUI macro declarations without their plugin; use the
# installed 26.5 SDK until the complete Xcode toolchain is selected.
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    task_swift_args+=(--sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk --build-system native)
fi
task_archs=(${METER_ARCHS:-$(uname -m)})
task_bins=()
for task_arch in "${task_archs[@]}"; do
    swift build -c release "${task_swift_args[@]}" --arch "$task_arch" --scratch-path ".build/$task_arch"
    task_bins+=("$(swift build -c release "${task_swift_args[@]}" --arch "$task_arch" --scratch-path ".build/$task_arch" --show-bin-path)/codex-meter")
done
task_app="$task_root/dist/Codex Meter.app"
mkdir -p "$task_app/Contents/MacOS" "$task_app/Contents/Resources"
if [ "${#task_bins[@]}" -gt 1 ]; then
    lipo -create "${task_bins[@]}" -output "$task_app/Contents/MacOS/codex-meter"
else
    cp "${task_bins[0]}" "$task_app/Contents/MacOS/codex-meter"
fi
mkdir -p "$task_app/Contents/Frameworks"
task_sparkle=$(python3 - <<'PYSPARKLE'
from pathlib import Path
matches=list(Path('.vendor').glob('**/macos-arm64_x86_64/Sparkle.framework'))
assert len(matches)==1, 'Expected one pinned Sparkle framework'
print(matches[0])
PYSPARKLE
)
ditto "$task_sparkle" "$task_app/Contents/Frameworks/Sparkle.framework"
cp "$task_root/Info.plist" "$task_app/Contents/Info.plist"
cp -R "$task_root/Integration" "$task_app/Contents/Resources/"
cp .vendor/sparkle-tools/LICENSE "$task_app/Contents/Resources/Sparkle-LICENSE.txt"
task_iconset="$task_root/dist/AppIcon.iconset"
task_icon_sdk=()
if [ -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk ]; then
    task_icon_sdk=(-sdk /Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk)
fi
swift "${task_icon_sdk[@]}" "$task_root/scripts/generate-icon.swift" "$task_iconset"
iconutil -c icns "$task_iconset" -o "$task_app/Contents/Resources/AppIcon.icns"
# Developer ID can be added for notarized releases; ad-hoc builds use EdDSA update authentication.
codesign --force --sign "${METER_SIGN_IDENTITY:--}" --identifier local.codex-meter.app "$task_app"
codesign --verify --deep --strict "$task_app"
echo "$task_app"
