#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v whisper-cli >/dev/null 2>&1 && ! command -v whisper-cpp >/dev/null 2>&1; then
    echo "Error: build whisper.cpp and add whisper-cli to PATH before starting OpenWispr." >&2
    exit 1
fi

swift build -c release
bash scripts/bundle-app.sh .build/release/open-wispr OpenWispr.app dev
exec OpenWispr.app/Contents/MacOS/open-wispr start
