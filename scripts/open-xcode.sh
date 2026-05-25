#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

if ! command -v xcodegen >/dev/null 2>&1; then
  echo "FEHLER: xcodegen fehlt. Installiere es mit: brew install xcodegen"
  exit 1
fi

xcodegen generate
xed NeoQuill.xcodeproj
