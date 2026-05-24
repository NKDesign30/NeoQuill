#!/usr/bin/env bash
# Prüft, dass die aktuelle VERSION im CHANGELOG dokumentiert ist.

set -euo pipefail

cd "$(dirname "$0")/.."

CHANGELOG_PATH="${NEOQUILL_CHANGELOG:-CHANGELOG.md}"
VERSION_VALUE="${1:-$(tr -d '[:space:]' < VERSION)}"

if [ -z "$VERSION_VALUE" ]; then
  echo "FEHLER: VERSION ist leer."
  exit 1
fi

if [ ! -f "$CHANGELOG_PATH" ]; then
  echo "FEHLER: $CHANGELOG_PATH fehlt."
  exit 1
fi

HEADING_PATTERN="^## \\[$VERSION_VALUE\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$"
if ! grep -Eq "$HEADING_PATTERN" "$CHANGELOG_PATH"; then
  echo "FEHLER: $CHANGELOG_PATH enthält keinen Release-Abschnitt für $VERSION_VALUE."
  echo "Erwartet: ## [$VERSION_VALUE] - YYYY-MM-DD"
  exit 1
fi

SECTION="$(awk -v version="$VERSION_VALUE" '
  $0 ~ "^## \\[" version "\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" {
    in_section = 1
    next
  }
  in_section && $0 ~ "^## \\[" {
    exit
  }
  in_section {
    print
  }
' "$CHANGELOG_PATH")"

if ! printf '%s\n' "$SECTION" | grep -Eq '^- .+'; then
  echo "FEHLER: Changelog-Abschnitt $VERSION_VALUE enthält keinen Bullet."
  exit 1
fi

echo "Changelog OK: $CHANGELOG_PATH enthält $VERSION_VALUE."
