#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

bash scripts/build-whisper.sh
bash scripts/build-swift.sh
APP_DIR="${OPEN_WISPR_DEV_APP_DIR:-/tmp/OpenWispr.app}"
bash scripts/bundle-app.sh .build/release/open-wispr "$APP_DIR" dev
exec "$APP_DIR/Contents/MacOS/open-wispr" start
