#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$(uname -m)-apple-macosx13.0"
MODE="${1:-release}"
case "$MODE" in
    debug) SWIFT_FLAGS=(-Onone -g) ;;
    release) SWIFT_FLAGS=(-O) ;;
    *) echo "Usage: bash scripts/build-swift.sh [debug|release]" >&2; exit 2 ;;
esac
# Build directly with swiftc so a broken SwiftPM manifest loader cannot block the app.
mkdir -p "$REPO_DIR/.build/$MODE"
BUILD_DIR="$(mktemp -d "$REPO_DIR/.build/swift-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

(
    cd "$BUILD_DIR"
    swiftc "${SWIFT_FLAGS[@]}" -swift-version 5 -target "$TARGET" \
        -emit-module -emit-object -parse-as-library \
        -module-name OpenWisprLib \
        -emit-module-path "$BUILD_DIR/OpenWisprLib.swiftmodule" \
        "$REPO_DIR"/Sources/OpenWisprLib/*.swift \
        -framework AppKit -framework AVFoundation -framework CoreAudio
)

swiftc "${SWIFT_FLAGS[@]}" -swift-version 5 -target "$TARGET" \
    -I "$BUILD_DIR" \
    "$REPO_DIR"/Sources/OpenWispr/*.swift "$BUILD_DIR"/*.o \
    -framework AppKit -framework AVFoundation -framework CoreAudio \
    -o "$REPO_DIR/.build/$MODE/open-wispr"

echo "Built $REPO_DIR/.build/$MODE/open-wispr"
