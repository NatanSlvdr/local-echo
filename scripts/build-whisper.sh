#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_TAG="v1.9.4"
WHISPER_DIR="$REPO_DIR/.build/whisper.cpp-$WHISPER_TAG"
WHISPER_BINARY="$REPO_DIR/.build/whisper-cli"
WHISPER_SERVER="$REPO_DIR/.build/whisper-server"
CACHE_STAMP="$REPO_DIR/.build/whisper-cli.cache-key"

if [ "${1:-}" != "" ] && [ "$1" != "--force" ]; then
    echo "Usage: bash scripts/build-whisper.sh [--force]" >&2
    exit 2
fi

# Rebuild when the pinned version, architecture, or build recipe changes.
CACHE_KEY="$WHISPER_TAG-$(uname -m)-$(shasum -a 256 "$0" | awk '{print $1}')"
if [ "${1:-}" != "--force" ] && [ -x "$WHISPER_BINARY" ] && [ -x "$WHISPER_SERVER" ] &&
   [ -f "$CACHE_STAMP" ] && [ "$(cat "$CACHE_STAMP")" = "$CACHE_KEY" ]; then
    echo "Using cached $WHISPER_BINARY"
    exit 0
fi

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required to build whisper-cli." >&2
    exit 1
fi

mkdir -p "$REPO_DIR/.build"
rm -f "$CACHE_STAMP"
if [ ! -d "$WHISPER_DIR/.git" ]; then
    git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

CMAKE_POLICY_VERSION_MINIMUM=3.10 cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_CCACHE=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_TESTS=OFF
cmake --build "$WHISPER_DIR/build" --target whisper-cli whisper-server --parallel
cp "$WHISPER_DIR/build/bin/whisper-cli" "$WHISPER_BINARY"
cp "$WHISPER_DIR/build/bin/whisper-server" "$WHISPER_SERVER"
printf '%s\n' "$CACHE_KEY" > "$CACHE_STAMP"

echo "Built $WHISPER_BINARY"
