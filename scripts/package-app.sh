#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "${1:-}" != "--skip-build" ]]; then swift build -c release --jobs 2; fi
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
staging="$(mktemp -d "$PWD/dist/.open-mouse-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Open Mouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$binary_dir/OpenMouse" "$app/Contents/MacOS/OpenMouse"
cp Resources/Info.plist "$app/Contents/Info.plist"
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Licenses/"
cp LICENSES/*.txt "$app/Contents/Resources/Licenses/"
codesign --force --sign - --identifier io.github.mauriciogoulartt.open-mouse "$app"
codesign --verify --strict "$app"
if [[ -d "dist/Open Mouse.app" ]]; then rm -rf "dist/Open Mouse.app"; fi
mv "$app" "dist/Open Mouse.app"
ditto -c -k --sequesterRsrc --keepParent "dist/Open Mouse.app" dist/OpenMouse-macOS.zip
printf '%s\n' "$PWD/dist/Open Mouse.app"
