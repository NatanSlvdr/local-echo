#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

MODE="${1:-debug}"
if [ "$MODE" != "debug" ] && [ "$MODE" != "release" ]; then
    echo "Usage: bash scripts/dev.sh [debug|release]" >&2
    exit 2
fi

if pgrep -x open-wispr >/dev/null; then
    echo "OpenWispr is already running. Quit it from the menu bar before rebuilding." >&2
    exit 1
fi

bash scripts/build-whisper.sh
bash scripts/build-swift.sh "$MODE"
if [ -z "${OPEN_WISPR_CODESIGN_IDENTITY:-}" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')"
    if [ -n "$SIGNING_IDENTITY" ]; then
        export OPEN_WISPR_CODESIGN_IDENTITY="$SIGNING_IDENTITY"
        echo "Signing with an Apple Development identity for stable microphone permission."
    fi
fi
APP_DIR="${OPEN_WISPR_DEV_APP_DIR:-$HOME/Library/Application Support/OpenWispr/dev/OpenWispr.app}"
bash scripts/bundle-app.sh ".build/$MODE/open-wispr" "$APP_DIR" dev
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP_DIR"
LOG_FILE="$HOME/.config/open-wispr/dev.log"
mkdir -p "$(dirname "$LOG_FILE")"
: > "$LOG_FILE"
echo "OpenWispr log: $LOG_FILE"
open -a "$APP_DIR" --stdout "$LOG_FILE" --stderr "$LOG_FILE" --args start
