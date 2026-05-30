#!/usr/bin/env bash
# Publish a notarized NeoQuill release to the public update channel.
#
# Prerequisites:
#   - dist/NeoQuill-vX.Y.Z-*.dmg               (primary Direct-Sale artefact)
#   - dist/NeoQuill-vX.Y.Z-*.dmg.sha256
#   - dist/NeoQuill-vX.Y.Z-*.zip               (legacy/scripted fallback)
#   - dist/NeoQuill-vX.Y.Z-*.zip.sha256
#   - dist/NeoQuill-vX.Y.Z-*.json              (build manifest next to ZIP)
#
# What this script does:
#   1. Uses the newest JSON manifest as source of truth, requires matching
#      DMG/ZIP artefacts plus sidecars, and runs generate_appcast against the
#      matching DMG. Sparkle reads its Info.plist for version metadata and signs
#      the entry with the Sparkle EdDSA private key stored in the macOS Keychain.
#   2. Copies the generated appcast.xml to the repo root.
#   3. Commits the appcast.xml on the current branch.
#   4. Creates (or updates) a GitHub Release for tag vX.Y.Z and uploads the
#      DMG, ZIP, SHA256 sidecars and manifest as assets.
#
# Usage:
#   ./scripts/publish-update.sh                                # publish current VERSION
#   ./scripts/publish-update.sh --dry-run                      # show what would happen
#   ./scripts/publish-update.sh --skip-push                    # commit appcast but don't push or release
#
# Environment:
#   NEOQUILL_GITHUB_REPO   (default: NKDesign30/NeoQuill)
#   NEOQUILL_SPARKLE_BIN   (default: ~/.neoquill-signing/sparkle/bin)

set -euo pipefail

cd "$(dirname "$0")/.."

DRY_RUN=0
SKIP_PUSH=0
for arg in "$@"; do
  case "$arg" in
    --dry-run)   DRY_RUN=1 ;;
    --skip-push) SKIP_PUSH=1 ;;
    --help|-h)
      sed -n '2,22p' "$0"
      exit 0
      ;;
    *) echo "Unbekanntes Flag: $arg"; exit 1 ;;
  esac
done

REPO="${NEOQUILL_GITHUB_REPO:-NKDesign30/NeoQuill}"
SPARKLE_BIN="${NEOQUILL_SPARKLE_BIN:-$HOME/.neoquill-signing/sparkle/bin}"
VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
TAG_NAME="v$VERSION_VALUE"

if ! command -v python3 >/dev/null 2>&1; then
  echo "FEHLER: python3 fehlt."
  exit 1
fi

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "FEHLER: generate_appcast nicht gefunden in $SPARKLE_BIN"
  echo "  Sparkle Release-Bundle entpacken nach ~/.neoquill-signing/sparkle/ oder"
  echo "  NEOQUILL_SPARKLE_BIN auf den richtigen Pfad setzen."
  exit 1
fi

latest_dist_file() {
  local pattern="$1"
  python3 - "$pattern" <<'PY'
import glob
import os
import re
import sys

files = glob.glob(sys.argv[1])

def sort_key(path):
    name = os.path.basename(path)
    match = re.search(r"-build(\d+)-", name)
    build = int(match.group(1)) if match else -1
    return (build, os.path.getmtime(path), name)

if files:
    print(max(files, key=sort_key))
PY
}

manifest_value() {
  local path="$1"
  local key="$2"
  python3 - "$path" "$key" <<'PY'
import json
import sys

with open(sys.argv[1], "r", encoding="utf-8") as handle:
    data = json.load(handle)

value = data.get(sys.argv[2])
if isinstance(value, bool):
    print("true" if value else "false")
elif value is None:
    print("")
else:
    print(value)
PY
}

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "FEHLER: $label fehlt: $path"
    exit 1
  fi
}

require_main_for_public_publish() {
  if [ "$DRY_RUN" = "1" ] || [ "$SKIP_PUSH" = "1" ]; then
    return
  fi
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  if [ "$branch" != "main" ]; then
    echo "FEHLER: Public publish muss auf main laufen; aktueller Branch ist '$branch'."
    echo "  --dry-run für Preview oder --skip-push für lokalen Appcast-Commit nutzen."
    exit 1
  fi
}

require_clean_tracked_worktree() {
  if [ "$DRY_RUN" = "1" ]; then
    return
  fi
  if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "FEHLER: Git-Working-Tree enthält tracked Änderungen."
    echo "  Erst committen/stashen. publish-update committet nur appcast.xml."
    exit 1
  fi
}

MANIFEST_PATH="$(latest_dist_file "dist/NeoQuill-${TAG_NAME}-*.json")"
if [ -z "$MANIFEST_PATH" ]; then
  echo "FEHLER: kein dist/NeoQuill-${TAG_NAME}-*.json gefunden."
  echo "  Erst ./scripts/package-release.sh --strict-distribution --notarize ausführen."
  exit 1
fi

MANIFEST_VERSION="$(manifest_value "$MANIFEST_PATH" version)"
MANIFEST_ARCHIVE="$(manifest_value "$MANIFEST_PATH" archive)"
MANIFEST_BUILD="$(manifest_value "$MANIFEST_PATH" build)"
MANIFEST_COMMIT="$(manifest_value "$MANIFEST_PATH" gitCommit)"

if [ "$MANIFEST_VERSION" != "$VERSION_VALUE" ]; then
  echo "FEHLER: Manifest-Version ist '$MANIFEST_VERSION', erwartet '$VERSION_VALUE'."
  exit 1
fi

if [ -z "$MANIFEST_ARCHIVE" ] || [ -z "$MANIFEST_BUILD" ] || [ -z "$MANIFEST_COMMIT" ]; then
  echo "FEHLER: Manifest ist unvollständig: $MANIFEST_PATH"
  exit 1
fi

if [[ "$MANIFEST_ARCHIVE" != NeoQuill-"$TAG_NAME"-*.zip ]]; then
  echo "FEHLER: Manifest-Archiv passt nicht zu $TAG_NAME: $MANIFEST_ARCHIVE"
  exit 1
fi

ZIP_PATH="dist/$MANIFEST_ARCHIVE"
DMG_PATH="dist/NeoQuill-${TAG_NAME}-build${MANIFEST_BUILD}-${MANIFEST_COMMIT}.dmg"

require_file "$ZIP_PATH" "ZIP"
require_file "$ZIP_PATH.sha256" "ZIP-SHA256"
require_file "$DMG_PATH" "DMG"
require_file "$DMG_PATH.sha256" "DMG-SHA256"

ASSETS=(
  "$DMG_PATH"
  "$DMG_PATH.sha256"
  "$ZIP_PATH"
  "$ZIP_PATH.sha256"
  "$MANIFEST_PATH"
)

require_main_for_public_publish
require_clean_tracked_worktree

echo "  Artefakte: ${ASSETS[*]}"

APPCAST_SOURCE_DIR="$(mktemp -d)"
trap 'rm -rf "$APPCAST_SOURCE_DIR"' EXIT

cp "$DMG_PATH" "$APPCAST_SOURCE_DIR/"

echo "[1/4] generate_appcast über $APPCAST_SOURCE_DIR/"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde laufen: $SPARKLE_BIN/generate_appcast --download-url-prefix https://github.com/${REPO}/releases/download/${TAG_NAME}/ $APPCAST_SOURCE_DIR/"
else
  "$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/${REPO}/releases/download/${TAG_NAME}/" \
    "$APPCAST_SOURCE_DIR/"
fi

GENERATED_APPCAST="$APPCAST_SOURCE_DIR/appcast.xml"
if [ "$DRY_RUN" != "1" ] && [ ! -f "$GENERATED_APPCAST" ]; then
  echo "FEHLER: generate_appcast hat keinen appcast geschrieben: $GENERATED_APPCAST"
  exit 1
fi

echo "[2/4] appcast.xml ins Repo-Root kopieren + diffen"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde kopieren: $GENERATED_APPCAST → ./appcast.xml"
else
  cp "$GENERATED_APPCAST" ./appcast.xml
  git add appcast.xml
  if git diff --cached --quiet appcast.xml 2>/dev/null; then
    echo "  appcast.xml hat sich nicht geändert."
  else
    git --no-pager diff --cached --stat appcast.xml
  fi
fi

echo "[3/4] Commit appcast.xml"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde commiten: appcast.xml für $TAG_NAME"
elif git diff --cached --quiet appcast.xml 2>/dev/null; then
  echo "  Nichts zu commiten — appcast.xml bereits auf dem Stand."
else
  git commit -m "chore(release): publish appcast for $TAG_NAME"
  if [ "$SKIP_PUSH" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    git push origin "$BRANCH"
  fi
fi

echo "[4/4] GitHub Release für $TAG_NAME + Assets hochladen"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde gh release create/edit $TAG_NAME mit ${ASSETS[*]}"
elif [ "$SKIP_PUSH" = "1" ]; then
  echo "  --skip-push gesetzt → GitHub Release wird übersprungen."
else
  CHANGELOG_BODY="$(awk -v v="$VERSION_VALUE" '
    /^## \[/ { if (in_section) exit; if (index($0, "[" v "]")) { in_section=1; next } }
    in_section { print }
  ' CHANGELOG.md)"

  if gh release view "$TAG_NAME" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG_NAME" "${ASSETS[@]}" --clobber --repo "$REPO"
    if [ -n "$CHANGELOG_BODY" ]; then
      gh release edit "$TAG_NAME" --notes "$CHANGELOG_BODY" --repo "$REPO"
    fi
  else
    if [ -n "$CHANGELOG_BODY" ]; then
      gh release create "$TAG_NAME" "${ASSETS[@]}" \
        --title "NeoQuill $TAG_NAME" \
        --notes "$CHANGELOG_BODY" \
        --repo "$REPO"
    else
      gh release create "$TAG_NAME" "${ASSETS[@]}" \
        --title "NeoQuill $TAG_NAME" \
        --generate-notes \
        --repo "$REPO"
    fi
  fi
fi

echo ""
echo "publish-update fertig. Sparkle-Clients sollten innerhalb von ~5min die neue Version sehen."
echo "  Appcast: https://raw.githubusercontent.com/${REPO}/main/appcast.xml"
echo "  Release: https://github.com/${REPO}/releases/tag/${TAG_NAME}"
