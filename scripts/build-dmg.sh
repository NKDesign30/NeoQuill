#!/usr/bin/env bash
# Build a branded, signed and notarized NeoQuill installer DMG.
#
# Prerequisites:
#   - .build/release/NeoQuill.app produced by scripts/build-app.sh --release
#   - Developer ID Application certificate in the macOS Keychain
#   - notarytool keychain profile in $NEOQUILL_NOTARY_PROFILE
#   - create-dmg via `brew install create-dmg`
#
# Output:
#   dist/NeoQuill-vX.Y.Z-buildN-<commit>.dmg
#   dist/NeoQuill-vX.Y.Z-buildN-<commit>.dmg.sha256
#
# Usage:
#   ./scripts/build-dmg.sh                          # build + sign DMG (no notarize)
#   ./scripts/build-dmg.sh --notarize               # also notarize + staple
#   ./scripts/build-dmg.sh --notarize --notary-profile <profile>
#   ./scripts/build-dmg.sh --app <path/to/NeoQuill.app>   # use a custom .app

set -euo pipefail

cd "$(dirname "$0")/.."

source scripts/lib/notary-profile.sh

APP=""
NOTARIZE=0
NOTARY_PROFILE="${NEOQUILL_NOTARY_PROFILE:-}"

while [ $# -gt 0 ]; do
  case "$1" in
    --notarize)         NOTARIZE=1 ;;
    --notary-profile)
        shift
        if [ -z "${1:-}" ]; then
          echo "FEHLER: --notary-profile braucht einen Keychain-Profilnamen."
          exit 1
        fi
        NOTARY_PROFILE="$1"
        ;;
    --app)
        shift
        APP="${1:-}"
        ;;
    --help|-h)
        sed -n '2,20p' "$0"
        exit 0
        ;;
    *) echo "Unbekanntes Flag: $1"; exit 1 ;;
  esac
  shift
done

if [ "$NOTARIZE" = "1" ]; then
  if [ -z "$NOTARY_PROFILE" ]; then
    NOTARY_PROFILE="$(neoquill_resolve_notary_profile || true)"
  fi
  if [ -z "$NOTARY_PROFILE" ]; then
    echo "FEHLER: --notarize braucht --notary-profile oder NEOQUILL_NOTARY_PROFILE."
    neoquill_notary_profile_help
    exit 1
  fi
fi

if [ -z "$APP" ]; then
  BUILD_DIR="$(swift build -c release --show-bin-path)"
  APP="$BUILD_DIR/NeoQuill.app"
fi

if [ ! -d "$APP" ]; then
  echo "FEHLER: App-Bundle nicht gefunden: $APP"
  echo "  Erst ./scripts/build-app.sh --release --no-install --no-run ausführen."
  exit 1
fi

VERSION_VALUE="$(tr -d '[:space:]' < VERSION)"
TAG_NAME="v$VERSION_VALUE"

BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
GIT_COMMIT="$(/usr/libexec/PlistBuddy -c 'Print :NeoQuillGitCommit' "$APP/Contents/Info.plist")"

DIST_DIR="dist"
mkdir -p "$DIST_DIR"
DMG_BASENAME="NeoQuill-${TAG_NAME}-build${BUILD_NUMBER}-${GIT_COMMIT}"
DMG_PATH="${DIST_DIR}/${DMG_BASENAME}.dmg"
SHA_PATH="${DMG_PATH}.sha256"

echo "[1/5] Pre-flight"
echo "  App:        $APP"
echo "  Version:    $VERSION_VALUE (build $BUILD_NUMBER, commit $GIT_COMMIT)"
echo "  Output:     $DMG_PATH"
echo ""

# Signaturcheck — das DMG erbt zwar nicht die App-Signatur, aber wenn die App
# nicht Developer-ID-signiert ist, scheitert der spätere notarytool eh.
SIGNING_AUTHORITY="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
echo "  Authority:  $SIGNING_AUTHORITY"
if [[ "$SIGNING_AUTHORITY" != Developer\ ID\ Application:* ]]; then
  echo "  WARNUNG: App ist nicht Developer-ID-signiert; DMG-Notarisierung wird fehlschlagen."
fi
echo ""

echo "[2/5] create-dmg — branded layout"
STAGE_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto "$APP" "$STAGE_DIR/NeoQuill.app"

rm -f "$DMG_PATH"

create-dmg \
  --volname "Install NeoQuill" \
  --volicon "Sources/NeoQuill/Resources/AppIcon.icns" \
  --background "Resources/installer/background.png" \
  --window-pos 240 180 \
  --window-size 540 420 \
  --icon-size 96 \
  --text-size 12 \
  --icon "NeoQuill.app" 130 290 \
  --app-drop-link 410 290 \
  --hide-extension "NeoQuill.app" \
  --format UDZO \
  --filesystem APFS \
  --no-internet-enable \
  "$DMG_PATH" \
  "$STAGE_DIR"

# ---- Inject retina background ---------------------------------------------
# create-dmg only embeds the 1x background. Finder picks up an @2x variant
# from .background/ when present, which keeps the install window sharp on
# retina displays. Mount the just-built DMG read-write via `hdiutil convert`,
# drop the @2x PNG next to the 1x one and convert back to compressed RO.
echo ""
echo "[2.5/5] Polish DMG (retina background, hide system files)"
RW_DMG="${DMG_PATH%.dmg}-rw.dmg"
RW_MOUNT_ROOT="$(mktemp -d)"
RW_MOUNT="$RW_MOUNT_ROOT/dmg-rw"
hdiutil convert "$DMG_PATH" -format UDRW -o "$RW_DMG" -quiet
hdiutil attach "$RW_DMG" -mountpoint "$RW_MOUNT" -quiet

# Retina @2x background lives next to the 1x one
if [ -f "Resources/installer/background@2x.png" ]; then
  cp Resources/installer/background@2x.png "$RW_MOUNT/.background/"
fi

# Strip APFS housekeeping that shows up for users who have AppleShowAllFiles=1
rm -rf "$RW_MOUNT/.fseventsd" 2>/dev/null || true
rm -rf "$RW_MOUNT/.Trashes"   2>/dev/null || true
rm -rf "$RW_MOUNT/.Spotlight-V100" 2>/dev/null || true
# Volume icon must stay but mark as hidden so Finder respects it
SetFile -a V "$RW_MOUNT/.VolumeIcon.icns" 2>/dev/null || true

hdiutil detach "$RW_MOUNT" -force -quiet
rm -f "$DMG_PATH"
hdiutil convert "$RW_DMG" -format UDZO -o "$DMG_PATH" -quiet
rm -f "$RW_DMG"
rm -rf "$RW_MOUNT_ROOT"

if [ ! -f "$DMG_PATH" ]; then
  echo "FEHLER: DMG wurde nicht erzeugt: $DMG_PATH"
  exit 1
fi

echo ""
echo "[3/5] DMG signieren mit Developer ID"
DEVID="$(security find-identity -v -p codesigning | grep -i "Developer ID Application" | head -1 | awk '{print $2}')"
if [ -z "$DEVID" ]; then
  echo "  WARNUNG: kein Developer-ID-Cert in der Keychain — DMG bleibt unsigniert."
else
  codesign --sign "$DEVID" --timestamp "$DMG_PATH"
  codesign --verify --verbose=2 "$DMG_PATH" 2>&1 | tail -3
fi

if [ "$NOTARIZE" = "1" ]; then
  echo ""
  echo "[4/5] Notarization über Apple ($NOTARY_PROFILE)"
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "  Stapler attach"
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo ""
  echo "[4/5] Notarization übersprungen (--notarize nicht gesetzt)"
fi

echo ""
echo "[5/5] Manifest + SHA256"
shasum -a 256 "$DMG_PATH" | tee "$SHA_PATH"

echo ""
echo "Fertig: $DMG_PATH"
du -h "$DMG_PATH"
