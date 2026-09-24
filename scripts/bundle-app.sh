#!/bin/bash
set -euo pipefail

BINARY="${1:-.build/release/open-wispr}"
APP_DIR="${2:-OpenWispr.app}"
VERSION="${3:-0.3.0}"
WHISPER_BINARY="${4:-.build/whisper-cli}"
if [ ! -x "$WHISPER_BINARY" ] && [ "$#" -lt 4 ]; then
    WHISPER_BINARY="$(command -v whisper-cli || true)"
fi

if [ -z "$WHISPER_BINARY" ] || [ ! -x "$WHISPER_BINARY" ]; then
    echo "whisper-cli not found. Run scripts/build-whisper.sh or pass its path as argument 4." >&2
    exit 1
fi

# A static build keeps the app independent of third-party runtime libraries.
EXTERNAL_LIBRARIES="$(otool -L "$WHISPER_BINARY" | awk 'NR > 1 && $1 !~ /^\/usr\/lib\// && $1 !~ /^\/System\/Library\// { print $1 }')"
if [ -n "$EXTERNAL_LIBRARIES" ]; then
    echo "whisper-cli has external libraries; rebuild it with scripts/build-whisper.sh:" >&2
    echo "$EXTERNAL_LIBRARIES" >&2
    exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/open-wispr"
cp "$WHISPER_BINARY" "$APP_DIR/Contents/MacOS/whisper-cli"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cp "$REPO_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
mkdir -p "$APP_DIR/Contents/Resources/Licenses"
cp "$REPO_DIR/Resources/WhisperLicense.txt" "$APP_DIR/Contents/Resources/Licenses/whisper.cpp.txt"

cat > "$APP_DIR/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>open-wispr</string>
    <key>CFBundleIdentifier</key>
    <string>com.human37.open-wispr</string>
    <key>CFBundleName</key>
    <string>OpenWispr</string>
    <key>CFBundleDisplayName</key>
    <string>OpenWispr</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>OpenWispr needs microphone access to record speech for transcription.</string>
</dict>
</plist>
PLIST

codesign --remove-signature "$APP_DIR/Contents/MacOS/whisper-cli"
codesign --remove-signature "$APP_DIR/Contents/MacOS/open-wispr"
codesign --sign - "$APP_DIR/Contents/MacOS/whisper-cli"
codesign --sign - --identifier com.human37.open-wispr "$APP_DIR"

echo "Built $APP_DIR"
