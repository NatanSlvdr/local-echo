#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WHISPER_TAG="v1.9.4"
WHISPER_DIR="$REPO_DIR/.build/whisper.cpp-$WHISPER_TAG"

if ! command -v cmake >/dev/null 2>&1; then
    echo "CMake is required to build whisper-cli." >&2
    exit 1
fi

mkdir -p "$REPO_DIR/.build"
if [ ! -d "$WHISPER_DIR/.git" ]; then
    git clone --depth 1 --branch "$WHISPER_TAG" https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

cmake -S "$WHISPER_DIR" -B "$WHISPER_DIR/build" \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=13.0 \
    -DBUILD_SHARED_LIBS=OFF \
    -DGGML_BACKEND_DL=OFF \
    -DGGML_NATIVE=OFF \
    -DGGML_OPENMP=OFF \
    -DGGML_METAL=ON \
    -DGGML_METAL_EMBED_LIBRARY=ON \
    -DWHISPER_BUILD_TESTS=OFF
cmake --build "$WHISPER_DIR/build" --target whisper-cli --parallel
cp "$WHISPER_DIR/build/bin/whisper-cli" "$REPO_DIR/.build/whisper-cli"

echo "Built $REPO_DIR/.build/whisper-cli"
