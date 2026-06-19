#!/usr/bin/env bash
# Prüft, ob der aktuelle NeoQuill-Stand als öffentlicher Direct-Release tragfähig ist.

set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/lib/notary-profile.sh

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

appcast_value() {
  local path="$1"
  local requested_version="$2"
  local key="$3"
  python3 - "$path" "$requested_version" "$key" <<'PY'
import sys
import xml.etree.ElementTree as ET

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"

path, requested_version, key = sys.argv[1:4]
root = ET.parse(path).getroot()

def local_name(tag):
    return tag.rsplit("}", 1)[-1] if "}" in tag else tag

def child_text(element, name):
    for child in element:
        if local_name(child.tag) == name:
            return (child.text or "").strip()
    return ""

def enclosure_for(item):
    return next((child for child in item if local_name(child.tag) == "enclosure"), None)

def appcast_short_version(item):
    enclosure = enclosure_for(item)
    enclosure_short_version = enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString", "") if enclosure is not None else ""
    return child_text(item, "shortVersionString") or enclosure_short_version

items = [element for element in root.iter() if local_name(element.tag) == "item"]
if not items:
    raise SystemExit("no appcast item found")

selected = None
for item in items:
    if appcast_short_version(item) == requested_version:
        selected = item
        break
if selected is None:
    selected = items[0]

enclosure = enclosure_for(selected)
enclosure_short_version = enclosure.get(f"{{{SPARKLE_NS}}}shortVersionString", "") if enclosure is not None else ""
enclosure_version = enclosure.get(f"{{{SPARKLE_NS}}}version", "") if enclosure is not None else ""

values = {
    "shortVersionString": child_text(selected, "shortVersionString") or enclosure_short_version,
    "version": child_text(selected, "version") or enclosure_version,
    "enclosureURL": enclosure.get("url", "") if enclosure is not None else "",
    "enclosureLength": enclosure.get("length", "") if enclosure is not None else "",
    "edSignature": enclosure.get(f"{{{SPARKLE_NS}}}edSignature", "") if enclosure is not None else "",
}

print(values.get(key, ""))
PY
}

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

echo "NeoQuill Market Readiness"
echo "Version: $VERSION_VALUE"
echo ""

require_command git
require_command gh
require_command python3
require_command shasum
require_command codesign
require_command security
require_command xcrun

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

MANIFEST_BUILD=""
MANIFEST_COMMIT=""
ARCHIVE_PATH=""
MANIFEST_PATH="$(latest_dist_file "dist/NeoQuill-v${VERSION_VALUE}-*.json")"
if [ -z "$MANIFEST_PATH" ]; then
  fail "Release-Manifest für $VERSION_VALUE fehlt in dist/"
else
  pass "Release-Manifest gefunden: $MANIFEST_PATH"
  MANIFEST_VERSION="$(manifest_value "$MANIFEST_PATH" version)"
  MANIFEST_BUILD="$(manifest_value "$MANIFEST_PATH" build)"
  MANIFEST_COMMIT="$(manifest_value "$MANIFEST_PATH" gitCommit)"
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

DMG_PATH=""
if [ -n "$MANIFEST_BUILD" ] && [ -n "$MANIFEST_COMMIT" ]; then
  DMG_PATH="dist/NeoQuill-v${VERSION_VALUE}-build${MANIFEST_BUILD}-${MANIFEST_COMMIT}.dmg"
else
  fail "Manifest enthält keinen Build/Commit für DMG-Abgleich"
fi

if [ -z "$DMG_PATH" ] || [ ! -f "$DMG_PATH" ]; then
  fail "DMG für Manifest-Build fehlt: $DMG_PATH"
else
  pass "DMG passend zum Manifest gefunden: $DMG_PATH"
  DMG_SHA_PATH="$DMG_PATH.sha256"
  if [ -f "$DMG_SHA_PATH" ]; then
    ACTUAL_DMG_SHA="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"
    RECORDED_DMG_SHA="$(awk '{print $1}' "$DMG_SHA_PATH")"
    if [ "$ACTUAL_DMG_SHA" = "$RECORDED_DMG_SHA" ]; then
      pass "DMG-SHA256 passt"
    else
      fail "DMG-SHA256 passt nicht zu $DMG_SHA_PATH"
    fi
  else
    fail "DMG-SHA256 fehlt: $DMG_SHA_PATH"
  fi

  if codesign --verify --verbose=2 "$DMG_PATH" >/dev/null 2>&1; then
    pass "DMG-Signatur ist gültig"
  else
    fail "DMG-Signatur ist ungültig"
  fi

  if xcrun stapler validate "$DMG_PATH" >/dev/null 2>&1; then
    pass "DMG hat ein gültiges stapled Notarization-Ticket"
  else
    fail "DMG hat kein gültiges stapled Notarization-Ticket"
  fi
fi

APPCAST_PATH="appcast.xml"
if [ -f "$APPCAST_PATH" ]; then
  pass "appcast.xml gefunden"
  if APPCAST_SHORT_VERSION="$(appcast_value "$APPCAST_PATH" "$VERSION_VALUE" shortVersionString)" \
     && APPCAST_BUILD_VERSION="$(appcast_value "$APPCAST_PATH" "$VERSION_VALUE" version)" \
     && APPCAST_ENCLOSURE_URL="$(appcast_value "$APPCAST_PATH" "$VERSION_VALUE" enclosureURL)" \
     && APPCAST_ENCLOSURE_LENGTH="$(appcast_value "$APPCAST_PATH" "$VERSION_VALUE" enclosureLength)" \
     && APPCAST_ED_SIGNATURE="$(appcast_value "$APPCAST_PATH" "$VERSION_VALUE" edSignature)"; then
    pass "appcast.xml ist parsebar"

    if [ "$APPCAST_SHORT_VERSION" = "$VERSION_VALUE" ]; then
      pass "Appcast-Version passt"
    else
      fail "Appcast-Version ist '$APPCAST_SHORT_VERSION', erwartet '$VERSION_VALUE'"
    fi

    if [ -n "$MANIFEST_BUILD" ] && [ "$APPCAST_BUILD_VERSION" = "$MANIFEST_BUILD" ]; then
      pass "Appcast-Build passt zum Manifest"
    elif [ -n "$APPCAST_BUILD_VERSION" ]; then
      fail "Appcast-Build ist '$APPCAST_BUILD_VERSION', Manifest-Build ist '$MANIFEST_BUILD'"
    else
      fail "Appcast-Build fehlt"
    fi

    EXPECTED_APPCAST_ARCHIVE=""
    EXPECTED_APPCAST_ARCHIVE_PATH=""
    if [ -n "${DMG_PATH:-}" ]; then
      EXPECTED_APPCAST_ARCHIVE="$(basename "$DMG_PATH")"
      EXPECTED_APPCAST_ARCHIVE_PATH="$DMG_PATH"
    elif [ -n "${ARCHIVE_PATH:-}" ] && [ -f "$ARCHIVE_PATH" ]; then
      EXPECTED_APPCAST_ARCHIVE="$(basename "$ARCHIVE_PATH")"
      EXPECTED_APPCAST_ARCHIVE_PATH="$ARCHIVE_PATH"
    fi

    EXPECTED_DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG_NAME}/${EXPECTED_APPCAST_ARCHIVE}"
    if [ -n "$EXPECTED_APPCAST_ARCHIVE" ] && [ "$APPCAST_ENCLOSURE_URL" = "$EXPECTED_DOWNLOAD_URL" ]; then
      pass "Appcast-Enclosure zeigt auf erwartetes Release-Artefakt"
    else
      fail "Appcast-Enclosure ist '$APPCAST_ENCLOSURE_URL', erwartet '$EXPECTED_DOWNLOAD_URL'"
    fi

    if [ -n "$EXPECTED_APPCAST_ARCHIVE_PATH" ]; then
      EXPECTED_APPCAST_LENGTH="$(wc -c < "$EXPECTED_APPCAST_ARCHIVE_PATH" | tr -d '[:space:]')"
      if [ "$APPCAST_ENCLOSURE_LENGTH" = "$EXPECTED_APPCAST_LENGTH" ]; then
        pass "Appcast-Enclosure-Length passt"
      else
        fail "Appcast-Enclosure-Length ist '$APPCAST_ENCLOSURE_LENGTH', erwartet '$EXPECTED_APPCAST_LENGTH'"
      fi
    fi

    if [ -n "$APPCAST_ED_SIGNATURE" ]; then
      pass "Appcast enthält EdDSA-Signatur"
    else
      fail "Appcast enthält keine EdDSA-Signatur"
    fi
  else
    fail "appcast.xml ist nicht parsebar"
  fi
else
  fail "appcast.xml fehlt"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Developer ID Application'; then
  pass "Developer ID Application Zertifikat ist in der Keychain"
else
  fail "Developer ID Application Zertifikat fehlt in der Keychain"
fi

if security find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Distribution'; then
  warn "Apple Distribution Zertifikat ist vorhanden; für Direct-Sale braucht NeoQuill trotzdem Developer ID Application"
fi

if NOTARY_PROFILE="$(neoquill_resolve_notary_profile 2>/dev/null)"; then
  pass "Notary-Profil ist verfügbar: $NOTARY_PROFILE"
else
  fail "kein Notary-Profil verfügbar: NEOQUILL_NOTARY_PROFILE fehlt und Keychain-Profil 'neoquill-notary' ist nicht nutzbar"
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
    EXPECTED_RELEASE_ASSETS=()
    if [ -n "${DMG_PATH:-}" ]; then
      EXPECTED_RELEASE_ASSETS+=("$(basename "$DMG_PATH")" "$(basename "$DMG_PATH").sha256")
    fi
    if [ -n "${ARCHIVE_PATH:-}" ]; then
      EXPECTED_RELEASE_ASSETS+=("$(basename "$ARCHIVE_PATH")" "$(basename "$ARCHIVE_PATH").sha256")
    fi
    if [ -n "${MANIFEST_PATH:-}" ]; then
      EXPECTED_RELEASE_ASSETS+=("$(basename "$MANIFEST_PATH")")
    fi

    MISSING_RELEASE_ASSETS=()
    for asset in "${EXPECTED_RELEASE_ASSETS[@]}"; do
      if ! grep -Fxq "$asset" <<<"$RELEASE_ASSETS"; then
        MISSING_RELEASE_ASSETS+=("$asset")
      fi
    done

    UNEXPECTED_RELEASE_ASSETS=()
    while IFS= read -r asset; do
      [ -n "$asset" ] || continue
      [[ "$asset" == NeoQuill-v${VERSION_VALUE}-* ]] || continue
      found=0
      for expected in "${EXPECTED_RELEASE_ASSETS[@]}"; do
        if [ "$asset" = "$expected" ]; then
          found=1
          break
        fi
      done
      if [ "$found" -eq 0 ]; then
        UNEXPECTED_RELEASE_ASSETS+=("$asset")
      fi
    done <<<"$RELEASE_ASSETS"

    if [ "${#MISSING_RELEASE_ASSETS[@]}" -eq 0 ] && [ "${#UNEXPECTED_RELEASE_ASSETS[@]}" -eq 0 ]; then
      pass "GitHub Release enthält exakt erwartete DMG, ZIP, SHA256-Dateien und Manifest"
    else
      [ "${#MISSING_RELEASE_ASSETS[@]}" -eq 0 ] || fail "GitHub Release Assets fehlen: ${MISSING_RELEASE_ASSETS[*]}"
      [ "${#UNEXPECTED_RELEASE_ASSETS[@]}" -eq 0 ] || fail "GitHub Release Assets sind unerwartet: ${UNEXPECTED_RELEASE_ASSETS[*]}"
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
