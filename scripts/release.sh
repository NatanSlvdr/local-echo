#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

REPO="NatanSlvdr/local-echo"
VERSION_FILE="Sources/LocalEchoLib/Version.swift"
CURRENT="$(sed -n 's/.*let version = "\([^"]*\)".*/\1/p' "$VERSION_FILE")"

usage() {
    echo "Usage: bash scripts/release.sh [--dry-run] [patch|minor|major|X.Y.Z]" >&2
    echo "Without a version, releases $CURRENT if it has no tag yet, otherwise the next patch version." >&2
    echo "--dry-run builds and zips the app without committing, tagging, or publishing." >&2
    exit 2
}

DRY_RUN=0
if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
    shift
fi

bump() {
    IFS=. read -r MAJOR MINOR PATCH <<< "$CURRENT"
    PATCH="${PATCH:-0}"
    case "$1" in
        patch) echo "$MAJOR.$MINOR.$((PATCH + 1))" ;;
        minor) echo "$MAJOR.$((MINOR + 1)).0" ;;
        major) echo "$((MAJOR + 1)).0.0" ;;
    esac
}

git fetch --quiet --tags origin main

case "${1:-}" in
    "")
        if git rev-parse -q --verify "refs/tags/v$CURRENT" >/dev/null; then
            VERSION="$(bump patch)"
        else
            VERSION="$CURRENT"
        fi
        ;;
    patch|minor|major) VERSION="$(bump "$1")" ;;
    -h|--help) usage ;;
    *) VERSION="$1" ;;
esac
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Invalid version: $VERSION (expected X.Y.Z)" >&2
    usage
fi
TAG="v$VERSION"

# Release only what is on origin/main, so the tag matches a published commit.
if [ "$DRY_RUN" = 0 ]; then
    if ! command -v gh >/dev/null 2>&1 || ! gh auth status >/dev/null 2>&1; then
        echo "The GitHub CLI must be installed and logged in (gh auth login)." >&2
        exit 1
    fi
    if [ "$(git rev-parse --abbrev-ref HEAD)" != "main" ]; then
        echo "Switch to main before releasing." >&2
        exit 1
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "Commit or stash your changes before releasing." >&2
        exit 1
    fi
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "Local main differs from origin/main. Pull or push first." >&2
        exit 1
    fi
fi
if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    echo "Tag $TAG already exists." >&2
    exit 1
fi

echo "Releasing Local-Echo $VERSION (current source version: $CURRENT)"

# The binary reads its version from Version.swift, so bump it before building.
if [ "$VERSION" != "$CURRENT" ]; then
    cp "$VERSION_FILE" .build/Version.swift.orig
    trap 'mv .build/Version.swift.orig "$VERSION_FILE"' EXIT
    sed -i '' "s/let version = \"$CURRENT\"/let version = \"$VERSION\"/" "$VERSION_FILE"
fi

if [ -z "${LOCAL_ECHO_CODESIGN_IDENTITY:-}" ]; then
    SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:/{print $2; exit}')"
    if [ -z "$SIGNING_IDENTITY" ]; then
        SIGNING_IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Apple Development:/{print $2; exit}')"
    fi
    if [ -n "$SIGNING_IDENTITY" ]; then
        export LOCAL_ECHO_CODESIGN_IDENTITY="$SIGNING_IDENTITY"
    fi
fi

# Bundle outside the checkout: iCloud Drive adds Finder metadata to apps in synced folders, which breaks signing.
STAGING_DIR="$(mktemp -d)"
APP_DIR="$STAGING_DIR/Local-Echo.app"
DIST_DIR=".build/dist"
ZIP="$DIST_DIR/Local-Echo-$VERSION.zip"
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

bash scripts/build-whisper.sh
bash scripts/build-swift.sh release
bash scripts/bundle-app.sh .build/release/local-echo "$APP_DIR" "$VERSION"
codesign --verify --strict "$APP_DIR"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP"
rm -rf "$STAGING_DIR"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256")
if [ "$DRY_RUN" = 1 ]; then
    echo "Dry run: built $ZIP without publishing."
    exit 0
fi

if [ "$VERSION" != "$CURRENT" ]; then
    git add "$VERSION_FILE"
    git commit --quiet -m "Release $VERSION"
    trap - EXIT
    rm .build/Version.swift.orig
fi
git tag -a "$TAG" -m "Local-Echo $VERSION"
git push --quiet origin main "$TAG"

NOTES="$(cat << NOTES
Requires an Apple Silicon Mac with macOS 13 or later.

Install or update by running this in Terminal:

\`\`\`bash
curl -fsSL https://raw.githubusercontent.com/$REPO/main/scripts/install.sh | bash
\`\`\`

To install manually instead, download \`Local-Echo-$VERSION.zip\`, unzip it, and move **Local-Echo.app** to **Applications**. This build is not notarized, so macOS blocks the first launch of a browser download: open it once, then choose **System Settings → Privacy & Security → Open Anyway**.

See the [setup guide](https://github.com/$REPO/blob/$TAG/docs/install-guide.md) for permissions.
NOTES
)"
gh release create "$TAG" "$ZIP" "$ZIP.sha256" \
    --title "Local-Echo $VERSION" \
    --notes "$NOTES" \
    --generate-notes \
    --verify-tag

echo "Released $TAG: $(gh release view "$TAG" --json url --jq .url)"
