#!/bin/bash
set -euo pipefail

PASS=0
FAIL=0

pass() { PASS=$((PASS + 1)); echo "  PASS: $1"; }
fail() { FAIL=$((FAIL + 1)); echo "  FAIL: $1"; }

echo "Local-Echo transcription integration tests"
echo "--------------------------------------------"

# Prefer the packaged executable when an app bundle has been built.
WHISPER_BIN=""
APP_DIR="${LOCAL_ECHO_DEV_APP_DIR:-$HOME/Library/Application Support/Local-Echo/dev/Local-Echo.app}"
if [ -x "$APP_DIR/Contents/MacOS/whisper-cli" ]; then
    WHISPER_BIN="$APP_DIR/Contents/MacOS/whisper-cli"
elif [ -x ".build/whisper-cli" ]; then
    WHISPER_BIN=".build/whisper-cli"
elif command -v whisper-cli &>/dev/null; then
    WHISPER_BIN="$(command -v whisper-cli)"
fi

if [ -z "$WHISPER_BIN" ]; then
    echo "SKIP: whisper-cli not found on PATH"
    exit 0
fi
pass "whisper binary found: $WHISPER_BIN"

# Find or download the tiny.en model (smallest, ~75 MB)
MODEL_SIZE="tiny.en"
MODEL_FILE="ggml-${MODEL_SIZE}.bin"
MODEL_PATH=""

for dir in \
    "$HOME/.config/local-echo/models" \
    "$HOME/.cache/whisper"; do
    if [ -f "$dir/$MODEL_FILE" ]; then
        MODEL_PATH="$dir/$MODEL_FILE"
        break
    fi
done

if [ -z "$MODEL_PATH" ]; then
    echo "Downloading $MODEL_SIZE model..."
    MODEL_DIR="$HOME/.config/local-echo/models"
    mkdir -p "$MODEL_DIR"
    MODEL_PATH="$MODEL_DIR/$MODEL_FILE"
    curl -L --progress-bar -o "$MODEL_PATH" \
        "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$MODEL_FILE"
fi
pass "Model available: $MODEL_PATH"

TMPDIR_TEST=$(mktemp -d /tmp/local-echo-test.XXXXXX)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Generate test audio using macOS text-to-speech
echo "Generating test audio..."
say -o "$TMPDIR_TEST/hello.aiff" "Hello world"
afconvert -f WAVE -d LEI16@16000 -c 1 "$TMPDIR_TEST/hello.aiff" "$TMPDIR_TEST/hello.wav"
pass "Generated hello.wav"

say -o "$TMPDIR_TEST/numbers.aiff" "One two three four five"
afconvert -f WAVE -d LEI16@16000 -c 1 "$TMPDIR_TEST/numbers.aiff" "$TMPDIR_TEST/numbers.wav"
pass "Generated numbers.wav"

# Test 1: Basic transcription
echo ""
echo "Running transcription tests..."
OUTPUT=$($WHISPER_BIN -m "$MODEL_PATH" -f "$TMPDIR_TEST/hello.wav" --no-timestamps -nt 2>/dev/null || true)
OUTPUT_LOWER=$(echo "$OUTPUT" | tr '[:upper:]' '[:lower:]')

if echo "$OUTPUT_LOWER" | grep -q "hello"; then
    pass "Transcribed 'hello' from audio"
else
    fail "Expected 'hello' in output, got: $OUTPUT"
fi

# Test 2: Numbers
OUTPUT=$($WHISPER_BIN -m "$MODEL_PATH" -f "$TMPDIR_TEST/numbers.wav" --no-timestamps -nt 2>/dev/null || true)
OUTPUT_LOWER=$(echo "$OUTPUT" | tr '[:upper:]' '[:lower:]')

if echo "$OUTPUT_LOWER" | grep -qE "one|two|three|four|five|1|2|3|4|5"; then
    pass "Transcribed numbers from audio"
else
    fail "Expected number words in output, got: $OUTPUT"
fi

# Test 3: The app finds its bundled whisper-server
BIN="$APP_DIR/Contents/MacOS/local-echo"
if [ ! -x "$BIN" ]; then
    BIN=".build/release/local-echo"
fi
if [ -x "$BIN" ]; then
    if $BIN status 2>&1 | grep -q "Whisper server: yes"; then
        pass "Binary detects whisper-server"
    else
        fail "Binary should detect whisper-server"
    fi
fi

echo ""
echo "--------------------------------------------"
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
