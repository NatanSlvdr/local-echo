#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TARGET="$(uname -m)-apple-macosx13.0"
# Build directly with swiftc so a broken SwiftPM manifest loader cannot block the app.
mkdir -p "$REPO_DIR/.build/release"
BUILD_DIR="$(mktemp -d "$REPO_DIR/.build/swift-build.XXXXXX")"
trap 'rm -rf "$BUILD_DIR"' EXIT

(
    cd "$BUILD_DIR"
    swiftc -O -swift-version 5 -target "$TARGET" \
        -emit-module -emit-object -parse-as-library \
        -module-name OpenWisprLib \
        -emit-module-path "$BUILD_DIR/OpenWisprLib.swiftmodule" \
        "$REPO_DIR"/Sources/OpenWisprLib/*.swift \
        -framework AppKit -framework AVFoundation -framework CoreAudio
)

swiftc -O -swift-version 5 -target "$TARGET" \
    -I "$BUILD_DIR" \
    "$REPO_DIR"/Sources/OpenWispr/*.swift "$BUILD_DIR"/*.o \
    -framework AppKit -framework AVFoundation -framework CoreAudio \
    -o "$REPO_DIR/.build/release/open-wispr"

echo "Built $REPO_DIR/.build/release/open-wispr"
