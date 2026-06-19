#!/usr/bin/env bash
# Lädt ein öffentliches NeoQuill-DMG, prüft Integrität, installiert in ein
# temporäres Verzeichnis und beweist, dass die App startet.

set -euo pipefail

cd "$(dirname "$0")/.."

REPO="${NEOQUILL_GITHUB_REPO:-NKDesign30/NeoQuill}"
TAG="${1:-latest}"
WAIT_SECONDS="${NEOQUILL_LAUNCH_SMOKE_WAIT_SECONDS:-6}"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "FEHLER: $1 fehlt."
    exit 1
  fi
}

require_command gh
require_command python3
require_command shasum
require_command hdiutil
require_command ditto
require_command codesign
require_command spctl
require_command open
require_command pgrep

if [ "$TAG" = "latest" ]; then
  RELEASE_JSON="$(gh release view --repo "$REPO" --json tagName,assets)"
  TAG="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tagName"])' <<<"$RELEASE_JSON")"
else
  RELEASE_JSON="$(gh release view "$TAG" --repo "$REPO" --json tagName,assets)"
fi

DMG_ASSET="$(python3 -c '
import json
import sys

assets = json.load(sys.stdin)["assets"]
names = [
    asset["name"]
    for asset in assets
    if asset["name"].endswith(".dmg") and asset["name"].startswith("NeoQuill-")
]
if len(names) != 1:
    raise SystemExit(f"expected exactly one NeoQuill DMG, found {names}")
print(names[0])
' <<<"$RELEASE_JSON")"
SHA_ASSET="${DMG_ASSET}.sha256"

TMP_DIR="$(mktemp -d)"
MOUNT_DIR="$TMP_DIR/mnt"
INSTALL_DIR="$TMP_DIR/install"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$MOUNT_DIR" "$INSTALL_DIR"

echo "NeoQuill Download/Install Smoke"
echo "Repo:    $REPO"
echo "Release: $TAG"
echo "DMG:     $DMG_ASSET"
echo ""

gh release download "$TAG" --repo "$REPO" --pattern "$DMG_ASSET" --dir "$TMP_DIR" >/dev/null
gh release download "$TAG" --repo "$REPO" --pattern "$SHA_ASSET" --dir "$TMP_DIR" >/dev/null

EXPECTED_SHA="$(awk '{print $1}' "$TMP_DIR/$SHA_ASSET")"
ACTUAL_SHA="$(shasum -a 256 "$TMP_DIR/$DMG_ASSET" | awk '{print $1}')"
if [ "$EXPECTED_SHA" != "$ACTUAL_SHA" ]; then
  echo "FEHLER: SHA256 mismatch."
  echo "  expected: $EXPECTED_SHA"
  echo "  actual:   $ACTUAL_SHA"
  exit 1
fi
echo "PASS: SHA256 passt"

hdiutil attach "$TMP_DIR/$DMG_ASSET" -nobrowse -mountpoint "$MOUNT_DIR" -quiet
ditto "$MOUNT_DIR/NeoQuill.app" "$INSTALL_DIR/NeoQuill.app"
hdiutil detach "$MOUNT_DIR" -quiet
echo "PASS: DMG mount + App-Kopie passt"

codesign --verify --deep --strict --verbose=2 "$INSTALL_DIR/NeoQuill.app" >/dev/null
echo "PASS: Codesign passt"

spctl --assess --type execute --verbose=4 "$INSTALL_DIR/NeoQuill.app" >/dev/null
echo "PASS: Gatekeeper akzeptiert notarized Developer ID"

open -n "$INSTALL_DIR/NeoQuill.app"
sleep "$WAIT_SECONDS"

PID="$(pgrep -f "$INSTALL_DIR/NeoQuill.app/Contents/MacOS/NeoQuill" | head -1 || true)"
if [ -z "$PID" ]; then
  echo "FEHLER: NeoQuill ist nach dem Start nicht gelaufen."
  exit 1
fi

VERSION="$(defaults read "$INSTALL_DIR/NeoQuill.app/Contents/Info" CFBundleShortVersionString)"
BUILD="$(defaults read "$INSTALL_DIR/NeoQuill.app/Contents/Info" CFBundleVersion)"
COMMIT="$(defaults read "$INSTALL_DIR/NeoQuill.app/Contents/Info" NeoQuillGitCommit 2>/dev/null || true)"

echo "PASS: App startet und bleibt laufen (pid=$PID)"
echo "Version: $VERSION build $BUILD ${COMMIT:+($COMMIT)}"

kill "$PID" 2>/dev/null || true
sleep 1
