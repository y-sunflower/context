#!/bin/sh
# Install the latest Context release into /Applications.
# Usage: curl -fsSL https://raw.githubusercontent.com/JosephBARBIERDARNAL/context/main/scripts/install.sh | sh
set -eu

REPO="JosephBARBIERDARNAL/context"
ASSET="Context-arm64.zip"
DEST="/Applications/Context.app"

if [ "$(uname -s)" != "Darwin" ]; then
    echo "error: Context is a macOS app" >&2
    exit 1
fi
if [ "$(uname -m)" != "arm64" ]; then
    echo "error: prebuilt releases are Apple Silicon only — build from source instead:" >&2
    echo "  git clone https://github.com/$REPO && cd context && just install" >&2
    exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading the latest Context release…"
if ! curl -fsSL -o "$tmp/$ASSET" \
    "https://github.com/$REPO/releases/latest/download/$ASSET"; then
    echo "error: could not download $ASSET from the latest release." >&2
    echo "There may be no published release yet (or a release build is still running):" >&2
    echo "  https://github.com/$REPO/releases" >&2
    exit 1
fi

ditto -x -k "$tmp/$ASSET" "$tmp/extracted"
[ -d "$tmp/extracted/Context.app" ] || { echo "error: unexpected archive layout" >&2; exit 1; }

rm -rf "$DEST"
ditto "$tmp/extracted/Context.app" "$DEST"
# The app is ad-hoc signed (not notarized); make sure Gatekeeper won't object.
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true

echo "Installed $DEST"
