#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-debug}"
if [ "$MODE" != "debug" ] && [ "$MODE" != "release" ]; then
    echo "Usage: bash scripts/dev.sh [debug|release]" >&2
    exit 2
fi

if pgrep -x local-echo >/dev/null; then
    echo "Local-Echo is already running. Quit it from the menu bar before rebuilding." >&2
    exit 1
fi

bash scripts/build-whisper.sh
bash scripts/build-swift.sh "$MODE"
if [ -z "${LOCAL_ECHO_CODESIGN_IDENTITY:-}" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')"
    if [ -n "$SIGNING_IDENTITY" ]; then
        export LOCAL_ECHO_CODESIGN_IDENTITY="$SIGNING_IDENTITY"
        echo "Signing with an Apple Development identity for stable microphone permission."
    fi
fi
APP_DIR="${LOCAL_ECHO_DEV_APP_DIR:-$HOME/Library/Application Support/Local-Echo/dev/Local-Echo.app}"
bash scripts/bundle-app.sh ".build/$MODE/local-echo" "$APP_DIR" dev
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
LOG_FILE="$HOME/.config/local-echo/dev.log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
echo "Local-Echo log: $LOG_FILE"
open -a "$APP_DIR" --stdout "$LOG_FILE" --stderr "$LOG_FILE" --args start
