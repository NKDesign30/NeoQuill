#!/usr/bin/env bash
# Prüft, ob der aktuelle NeoQuill-Stand als öffentlicher Direct-Release tragfähig ist.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
TAG_NAME="v$VERSION_VALUE"
REPO="${NEOQUILL_GITHUB_REPO:-NKDesign30/NeoQuill}"

FAILURES=0
WARNINGS=0

pass() {
  printf 'PASS: %s\n' "$1"
}

warn() {
  WARNINGS=$((WARNINGS + 1))
  printf 'WARN: %s\n' "$1"
}

fail() {
  FAILURES=$((FAILURES + 1))
  printf 'FAIL: %s\n' "$1"
}

require_command() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "command '$1' verfügbar"
  else
    fail "command '$1' fehlt"
  fi
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

echo "NeoQuill Market Readiness"
echo "Version: $VERSION_VALUE"
echo ""

require_command git
require_command gh
require_command python3
require_command shasum
require_command codesign
require_command security

if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
  fail "Git-Working-Tree ist dirty"
else
  pass "Git-Working-Tree ist clean"
fi

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$CURRENT_BRANCH" = "main" ]; then
  pass "aktueller Branch ist main"
else
  warn "aktueller Branch ist '$CURRENT_BRANCH', Release-Abschluss sollte auf main geprüft werden"
fi

if git rev-parse --verify dev >/dev/null 2>&1 && git rev-parse --verify main >/dev/null 2>&1; then
  DEV_SHA="$(git rev-parse dev)"
  MAIN_SHA="$(git rev-parse main)"
  if [ "$DEV_SHA" = "$MAIN_SHA" ]; then
    pass "dev und main zeigen auf denselben Commit"
  else
    fail "dev ($DEV_SHA) und main ($MAIN_SHA) sind nicht synchron"
  fi
else
  fail "lokale Branches dev/main fehlen"
fi

if git rev-parse --verify "$TAG_NAME" >/dev/null 2>&1; then
  TAG_SHA="$(git rev-parse "$TAG_NAME^{}")"
  HEAD_SHA="$(git rev-parse HEAD)"
  if [ "$TAG_SHA" = "$HEAD_SHA" ]; then
    pass "$TAG_NAME zeigt auf HEAD"
  else
    fail "$TAG_NAME zeigt auf $TAG_SHA, HEAD ist $HEAD_SHA"
  fi
else
  fail "lokaler Tag $TAG_NAME fehlt"
fi

if ./scripts/verify-changelog.sh "$VERSION_VALUE" >/dev/null; then
  pass "Changelog enthält $VERSION_VALUE"
else
  fail "Changelog enthält keinen gültigen Abschnitt für $VERSION_VALUE"
fi

MANIFEST_PATH="$(find dist -maxdepth 1 -type f -name "NeoQuill-v${VERSION_VALUE}-*.json" -print | sort | tail -1 || true)"
if [ -z "$MANIFEST_PATH" ]; then
  fail "Release-Manifest für $VERSION_VALUE fehlt in dist/"
else
  pass "Release-Manifest gefunden: $MANIFEST_PATH"
  MANIFEST_VERSION="$(manifest_value "$MANIFEST_PATH" version)"
  MANIFEST_DIRTY="$(manifest_value "$MANIFEST_PATH" gitDirty)"
  MANIFEST_ARCHIVE="$(manifest_value "$MANIFEST_PATH" archive)"
  MANIFEST_SHA="$(manifest_value "$MANIFEST_PATH" sha256)"
  MANIFEST_SIGNING="$(manifest_value "$MANIFEST_PATH" signingAuthority)"
  MANIFEST_NOTARIZED="$(manifest_value "$MANIFEST_PATH" notarized)"
  MANIFEST_STAPLED="$(manifest_value "$MANIFEST_PATH" stapled)"
  MANIFEST_CHANGELOG="$(manifest_value "$MANIFEST_PATH" changelog)"

  if [ "$MANIFEST_VERSION" = "$VERSION_VALUE" ]; then
    pass "Manifest-Version passt"
  else
    fail "Manifest-Version ist '$MANIFEST_VERSION', erwartet '$VERSION_VALUE'"
  fi

  if [ "$MANIFEST_DIRTY" = "clean" ]; then
    pass "Manifest wurde aus cleanem Git-Stand gebaut"
  else
    fail "Manifest meldet gitDirty=$MANIFEST_DIRTY"
  fi

  if [ "$MANIFEST_CHANGELOG" = "CHANGELOG.md#$VERSION_VALUE" ]; then
    pass "Manifest verweist auf passenden Changelog"
  else
    fail "Manifest-Changelog ist '$MANIFEST_CHANGELOG'"
  fi

  ARCHIVE_PATH="dist/$MANIFEST_ARCHIVE"
  if [ -f "$ARCHIVE_PATH" ]; then
    ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE_PATH" | awk '{print $1}')"
    if [ "$ACTUAL_SHA" = "$MANIFEST_SHA" ]; then
      pass "ZIP-SHA256 passt zum Manifest"
    else
      fail "ZIP-SHA256 passt nicht zum Manifest"
    fi
  else
    fail "ZIP fehlt: $ARCHIVE_PATH"
  fi

  if [[ "$MANIFEST_SIGNING" == Developer\ ID\ Application:* ]]; then
    pass "Manifest ist Developer-ID-signiert"
  else
    fail "Manifest ist nicht Developer-ID-signiert: $MANIFEST_SIGNING"
  fi

  if [ "$MANIFEST_NOTARIZED" = "true" ]; then
    pass "Manifest meldet notarized=true"
  else
    fail "Manifest meldet notarized=$MANIFEST_NOTARIZED"
  fi

  if [ "$MANIFEST_STAPLED" = "true" ]; then
    pass "Manifest meldet stapled=true"
  else
    fail "Manifest meldet stapled=$MANIFEST_STAPLED"
  fi
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Application'; then
  pass "Developer ID Application Zertifikat ist in der Keychain"
else
  fail "Developer ID Application Zertifikat fehlt in der Keychain"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Distribution'; then
  warn "Apple Distribution Zertifikat ist vorhanden; für Direct-Sale braucht NeoQuill trotzdem Developer ID Application"
fi

if [ -n "${NEOQUILL_NOTARY_PROFILE:-}" ]; then
  pass "NEOQUILL_NOTARY_PROFILE ist gesetzt"
else
  fail "NEOQUILL_NOTARY_PROFILE ist nicht gesetzt"
fi

if command -v gh >/dev/null 2>&1; then
  if RELEASE_JSON="$(gh release view "$TAG_NAME" --repo "$REPO" --json tagName,isDraft,isPrerelease,assets 2>/dev/null)"; then
    RELEASE_TAG="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["tagName"])' <<<"$RELEASE_JSON")"
    RELEASE_DRAFT="$(python3 -c 'import json,sys; print(str(json.load(sys.stdin)["isDraft"]).lower())' <<<"$RELEASE_JSON")"
    RELEASE_PRERELEASE="$(python3 -c 'import json,sys; print(str(json.load(sys.stdin)["isPrerelease"]).lower())' <<<"$RELEASE_JSON")"
    RELEASE_ASSETS="$(python3 -c 'import json,sys; print("\n".join(asset["name"] for asset in json.load(sys.stdin)["assets"]))' <<<"$RELEASE_JSON")"

    if [ "$RELEASE_TAG" = "$TAG_NAME" ]; then
      pass "GitHub Release $TAG_NAME existiert"
    else
      fail "GitHub Release Tag ist '$RELEASE_TAG'"
    fi
    if [ "$RELEASE_DRAFT" = "false" ] && [ "$RELEASE_PRERELEASE" = "false" ]; then
      pass "GitHub Release ist public und nicht prerelease"
    else
      fail "GitHub Release ist draft=$RELEASE_DRAFT prerelease=$RELEASE_PRERELEASE"
    fi
    if grep -Eq "^NeoQuill-v${VERSION_VALUE}-.*\\.zip$" <<<"$RELEASE_ASSETS" \
       && grep -Eq "^NeoQuill-v${VERSION_VALUE}-.*\\.zip\\.sha256$" <<<"$RELEASE_ASSETS" \
       && grep -Eq "^NeoQuill-v${VERSION_VALUE}-.*\\.json$" <<<"$RELEASE_ASSETS"; then
      pass "GitHub Release enthält ZIP, SHA256 und Manifest"
    else
      fail "GitHub Release Assets sind unvollständig"
    fi
  else
    fail "GitHub Release $TAG_NAME fehlt oder gh ist nicht authentifiziert"
  fi
fi

echo ""
if [ "$FAILURES" -eq 0 ]; then
  echo "Market readiness: PASS ($WARNINGS warnings)"
  exit 0
fi

echo "Market readiness: FAIL ($FAILURES failures, $WARNINGS warnings)"
exit 1
