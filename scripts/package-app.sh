#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
skip_build=false
keep_app=false
for argument in "$@"; do
  case "$argument" in
    --skip-build) skip_build=true ;;
    --keep-app) keep_app=true ;;
    *) printf 'Usage: %s [--skip-build] [--keep-app]\n' "$0" >&2; exit 1 ;;
  esac
done
if [[ "$skip_build" == false ]]; then swift build -c release --jobs 2; fi
binary_dir="$(swift build -c release --show-bin-path)"
mkdir -p dist
staging="$(mktemp -d "$PWD/dist/.open-mouse-package.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
app="$staging/Open Mouse.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources/Licenses"
cp "$binary_dir/OpenMouse" "$app/Contents/MacOS/OpenMouse"
cp Resources/Info.plist "$app/Contents/Info.plist"
iconset="$staging/AppIcon.iconset"
mkdir -p "$iconset"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}.png" >/dev/null
  retina=$((size * 2))
  sips -z "$retina" "$retina" Resources/AppIcon.png --out "$iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$iconset" -o "$app/Contents/Resources/AppIcon.icns"
build_number="${GITHUB_RUN_NUMBER:-1}"
[[ "$build_number" =~ ^[0-9]+$ ]] || { printf 'Invalid build number\n' >&2; exit 1; }
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $build_number" "$app/Contents/Info.plist"
source_revision="${GITHUB_SHA:-$(git rev-parse --verify HEAD 2>/dev/null || true)}"
if [[ "$source_revision" =~ ^[0-9a-f]{40}$ ]]; then
  /usr/libexec/PlistBuddy -c "Add :OpenMouseSourceRevision string $source_revision" "$app/Contents/Info.plist"
fi
cp LICENSE THIRD_PARTY_NOTICES.md "$app/Contents/Resources/Licenses/"
cp LICENSES/*.txt "$app/Contents/Resources/Licenses/"
codesign --force --sign - --identifier io.github.mauriciogoulartt.open-mouse "$app"
codesign --verify --strict "$app"
if [[ -d "dist/Open Mouse.app" ]]; then rm -rf "dist/Open Mouse.app"; fi
ditto -c -k --sequesterRsrc --keepParent "$app" dist/OpenMouse-macOS.zip
(cd dist && shasum -a 256 OpenMouse-macOS.zip > OpenMouse-macOS.zip.sha256)
if [[ "$keep_app" == true ]]; then
  mv "$app" "dist/Open Mouse.app"
  printf '%s\n' "$PWD/dist/Open Mouse.app"
else
  # Leave only an archive by default. Development/rollback bundles otherwise
  # appear as extra installed applications in Spotlight and Launch Services.
  printf '%s\n' "$PWD/dist/OpenMouse-macOS.zip"
fi
