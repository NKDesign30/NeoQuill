#!/usr/bin/env bash
# Publish a notarized NeoQuill release to the public update channel.
#
# Prerequisites (all produced by scripts/package-release.sh --strict-distribution --notarize):
#   - dist/NeoQuill-vX.Y.Z-*.zip               (Developer ID signed + Apple notarized + stapled)
#   - dist/NeoQuill-vX.Y.Z-*.zip.sha256
#   - dist/NeoQuill-vX.Y.Z-*.json              (build manifest)
#
# What this script does:
#   1. Runs generate_appcast against dist/, which scans every ZIP, reads its
#      Info.plist for version metadata and signs the entry with the Sparkle
#      EdDSA private key stored in the macOS Keychain.
#   2. Copies the generated appcast.xml to the repo root.
#   3. Commits the appcast.xml on the current branch.
#   4. Creates (or updates) a GitHub Release for tag vX.Y.Z and uploads the
#      ZIP, SHA256 and manifest as assets.
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

if [ ! -x "$SPARKLE_BIN/generate_appcast" ]; then
  echo "FEHLER: generate_appcast nicht gefunden in $SPARKLE_BIN"
  echo "  Sparkle Release-Bundle entpacken nach ~/.neoquill-signing/sparkle/ oder"
  echo "  NEOQUILL_SPARKLE_BIN auf den richtigen Pfad setzen."
  exit 1
fi

ZIP_PATH=$(ls -1t dist/NeoQuill-${TAG_NAME}-*.zip 2>/dev/null | head -1 || true)
if [ -z "$ZIP_PATH" ]; then
  echo "FEHLER: keine dist/NeoQuill-${TAG_NAME}-*.zip gefunden."
  echo "  Erst ./scripts/package-release.sh --strict-distribution --notarize ausführen."
  exit 1
fi

MANIFEST_PATH="${ZIP_PATH%.zip}.json"
SHA_PATH="${ZIP_PATH}.sha256"

echo "[1/4] generate_appcast über dist/"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde laufen: $SPARKLE_BIN/generate_appcast dist/"
else
  "$SPARKLE_BIN/generate_appcast" dist/
fi

GENERATED_APPCAST="dist/appcast.xml"
if [ "$DRY_RUN" != "1" ] && [ ! -f "$GENERATED_APPCAST" ]; then
  echo "FEHLER: generate_appcast hat keinen dist/appcast.xml geschrieben."
  exit 1
fi

echo "[2/4] appcast.xml ins Repo-Root kopieren + diffen"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde kopieren: $GENERATED_APPCAST → ./appcast.xml"
else
  cp "$GENERATED_APPCAST" ./appcast.xml
  if git diff --quiet appcast.xml 2>/dev/null; then
    echo "  appcast.xml hat sich nicht geändert."
  else
    git --no-pager diff --stat appcast.xml
  fi
fi

echo "[3/4] Commit appcast.xml"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde commiten: appcast.xml für $TAG_NAME"
elif git diff --quiet appcast.xml 2>/dev/null && git diff --cached --quiet appcast.xml 2>/dev/null; then
  echo "  Nichts zu commiten — appcast.xml bereits auf dem Stand."
else
  git add appcast.xml
  git commit -m "chore(release): publish appcast for $TAG_NAME"
  if [ "$SKIP_PUSH" != "1" ]; then
    BRANCH="$(git rev-parse --abbrev-ref HEAD)"
    git push origin "$BRANCH"
  fi
fi

echo "[4/4] GitHub Release für $TAG_NAME + Assets hochladen"
if [ "$DRY_RUN" = "1" ]; then
  echo "  würde gh release create/edit $TAG_NAME mit $ZIP_PATH"
elif [ "$SKIP_PUSH" = "1" ]; then
  echo "  --skip-push gesetzt → GitHub Release wird übersprungen."
else
  CHANGELOG_BODY="$(awk -v v="$VERSION_VALUE" '
    /^## \[/ { if (in_section) exit; if (index($0, "[" v "]")) { in_section=1; next } }
    in_section { print }
  ' CHANGELOG.md)"

  if gh release view "$TAG_NAME" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$TAG_NAME" "$ZIP_PATH" "$SHA_PATH" "$MANIFEST_PATH" \
      --clobber --repo "$REPO"
    if [ -n "$CHANGELOG_BODY" ]; then
      gh release edit "$TAG_NAME" --notes "$CHANGELOG_BODY" --repo "$REPO"
    fi
  else
    if [ -n "$CHANGELOG_BODY" ]; then
      gh release create "$TAG_NAME" "$ZIP_PATH" "$SHA_PATH" "$MANIFEST_PATH" \
        --title "NeoQuill $TAG_NAME" \
        --notes "$CHANGELOG_BODY" \
        --repo "$REPO"
    else
      gh release create "$TAG_NAME" "$ZIP_PATH" "$SHA_PATH" "$MANIFEST_PATH" \
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
