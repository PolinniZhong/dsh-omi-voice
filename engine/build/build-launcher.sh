#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/Omi.app"
EXECUTABLE="$APP/Contents/MacOS/OmiLauncher"
OMI_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

if ! printf '%s\n' "$OMI_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "invalid VERSION: expected MAJOR.MINOR.PATCH" >&2
  exit 1
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/OmiLauncher-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/OmiOS.icns" "$APP/Contents/Resources/OmiLauncher.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $OMI_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $OMI_VERSION" "$APP/Contents/Info.plist"

swiftc \
  -module-cache-path /tmp/omi-launcher-swift-cache \
  "$ROOT/Sources/OmiLauncher/main.swift" \
  -framework AppKit \
  -o "$EXECUTABLE"

codesign \
  --force \
  --deep \
  --sign - \
  --identifier com.wentuo.readaloud.launcher \
  "$APP"

echo "built: $APP ($OMI_VERSION)"
