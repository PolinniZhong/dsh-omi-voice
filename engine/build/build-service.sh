#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
APP="$ROOT/build/ReadAloudService.app"
EXECUTABLE="$APP/Contents/MacOS/ReadAloudService"
OMI_VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"

if ! printf '%s\n' "$OMI_VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "invalid VERSION: expected MAJOR.MINOR.PATCH" >&2
  exit 1
fi

# 完整 Xcode 的 Swift 与 SDK 会成套更新。允许调用方用 DEVELOPER_DIR
# 显式选择其他版本；未指定时优先使用标准安装位置的 Xcode。
if [[ -z "${DEVELOPER_DIR:-}" && -d "/Applications/Xcode.app/Contents/Developer" ]]; then
  export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$ROOT/Resources/ReadAloudService-Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Resources/Omi_logo.svg" "$APP/Contents/Resources/Omi_logo.svg"
cp "$ROOT/Resources/OmiOS.icns" "$APP/Contents/Resources/OmiOS.icns"
cp "$ROOT/Resources/OmiDSH.icns" "$APP/Contents/Resources/OmiDSH.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $OMI_VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $OMI_VERSION" "$APP/Contents/Info.plist"

swiftc \
  -module-cache-path /tmp/readaloud-swift-cache \
  "$ROOT"/Sources/ReadAloudConfig/KeychainStore.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudDiagnostics.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudPreferences.swift \
  "$ROOT"/Sources/ReadAloudConfig/DoubaoHTTPStreamingClient.swift \
  "$ROOT"/Sources/ReadAloudConfig/DoubaoTTSClient.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudTextPreparation.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudAudioCache.swift \
  "$ROOT"/Sources/ReadAloudConfig/PCMStreamPlayer.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudController.swift \
  "$ROOT"/Sources/ReadAloudConfig/ReadAloudSession.swift \
  "$ROOT"/Sources/ReadAloudConfig/HTMLListPlainTextConverter.swift \
  "$ROOT"/Sources/ReadAloudConfig/TTSBinaryProtocol.swift \
  "$ROOT"/Sources/ReadAloudService/main.swift \
  "$ROOT"/Sources/ReadAloudService/LocalTTSService.swift \
  -parse-as-library \
  -framework AppKit -framework AVFoundation -framework Carbon -framework Security -framework ServiceManagement -framework Network \
  -o "$EXECUTABLE"

codesign \
  --force \
  --deep \
  --sign - \
  --identifier com.wentuo.readaloud.service \
  "$APP"

echo "built: $APP ($OMI_VERSION)"
