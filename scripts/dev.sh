#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build-whisper.sh
swift build -c release
bash scripts/bundle-app.sh .build/release/open-wispr OpenWispr.app dev
exec OpenWispr.app/Contents/MacOS/open-wispr start
