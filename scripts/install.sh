#!/bin/bash
# Installs or updates Local-Echo from the latest GitHub release:
#   curl -fsSL https://raw.githubusercontent.com/NatanSlvdr/local-echo/main/scripts/install.sh | bash
# Set LOCAL_ECHO_VERSION (for example 0.46.0) to install a specific release.
set -euo pipefail

REPO="NatanSlvdr/local-echo"

fail() {
    echo "Error: $*" >&2
    exit 1
}

[ "$(uname -s)" = "Darwin" ] || fail "Local-Echo runs on macOS only."
[ "$(uname -m)" = "arm64" ] || fail "Local-Echo requires an Apple Silicon Mac."
MACOS_MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
[ "$MACOS_MAJOR" -ge 13 ] || fail "Local-Echo requires macOS 13 or later."

if [ -n "${LOCAL_ECHO_VERSION:-}" ]; then
    TAG="v${LOCAL_ECHO_VERSION#v}"
else
    # The latest release page redirects to its tag, which avoids the GitHub API rate limit.
    LATEST_URL="$(curl -fsSLo /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest")"
    TAG="${LATEST_URL##*/}"
    [[ "$TAG" == v* ]] || fail "Could not find the latest Local-Echo release."
fi
VERSION="${TAG#v}"
ZIP_NAME="Local-Echo-$VERSION.zip"
DOWNLOAD_URL="https://github.com/$REPO/releases/download/$TAG"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

echo "Downloading Local-Echo $VERSION..."
curl -fL --progress-bar -o "$TMP_DIR/$ZIP_NAME" "$DOWNLOAD_URL/$ZIP_NAME"
curl -fsSL -o "$TMP_DIR/$ZIP_NAME.sha256" "$DOWNLOAD_URL/$ZIP_NAME.sha256"
(cd "$TMP_DIR" && shasum -a 256 -c "$ZIP_NAME.sha256" >/dev/null) || fail "Checksum mismatch for $ZIP_NAME."
ditto -x -k "$TMP_DIR/$ZIP_NAME" "$TMP_DIR"
[ -d "$TMP_DIR/Local-Echo.app" ] || fail "$ZIP_NAME does not contain Local-Echo.app."

if [ -w /Applications ]; then
    INSTALL_DIR="/Applications"
else
    INSTALL_DIR="$HOME/Applications"
    mkdir -p "$INSTALL_DIR"
fi
APP="$INSTALL_DIR/Local-Echo.app"

if pgrep -x local-echo >/dev/null; then
    echo "Quitting the running Local-Echo..."
    osascript -e 'tell application id "com.natanslvdr.local-echo" to quit' >/dev/null 2>&1 || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x local-echo >/dev/null || break
        sleep 0.5
    done
    pkill -x local-echo 2>/dev/null || true
fi

rm -rf "$APP"
mv "$TMP_DIR/Local-Echo.app" "$APP"
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo "Installed Local-Echo $VERSION in $INSTALL_DIR."
open "$APP"
echo "Local-Echo is starting. Look for the waveform icon in the menu bar and grant Microphone and Accessibility access when asked."
