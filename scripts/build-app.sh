#!/usr/bin/env bash
# NeoQuill Build Script
# swift build + .app-Bundle + Auto-Sign + Install + Launch in einem Rutsch.
#
# Usage:
#   ./scripts/build-app.sh                # debug build, install, run
#   ./scripts/build-app.sh --release      # release build
#   ./scripts/build-app.sh --no-install   # nur build, kein /Applications copy
#   ./scripts/build-app.sh --no-run       # build + install, nicht starten
#   ./scripts/build-app.sh --clean        # vorher .build löschen

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="debug"
DO_INSTALL=1
DO_RUN=1
DO_CLEAN=0
ENTITLEMENTS="Resources/NeoQuill.entitlements"
VERSION_FILE="VERSION"

# Sign-Identity ermitteln:
# 1. ENV-Override:               NEOQUILL_SIGN_IDENTITY=<hash-or-name>
# 2. Bevorzugt: info@design-nk.de Cert (NK Design — aktiv)
# 3. Sonst erste verfügbare Apple-Cert (per SHA-1-Hash)
# 4. Fallback: ad-hoc ("-")
detect_sign_identity() {
  if [ -n "${NEOQUILL_SIGN_IDENTITY:-}" ]; then
    echo "$NEOQUILL_SIGN_IDENTITY"
    return
  fi
  local certs
  certs=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -E 'Apple Development|Developer ID Application' || true)
  local preferred
  preferred=$(echo "$certs" | grep -i "design-nk.de" | head -1 | awk '{print $2}')
  if [ -n "$preferred" ]; then
    echo "$preferred"
    return
  fi
  local hash
  hash=$(echo "$certs" | head -1 | awk '{print $2}')
  if [ -n "$hash" ]; then
    echo "$hash"
  else
    echo "-"
  fi
}
SIGN_IDENTITY=$(detect_sign_identity)
SIGN_LABEL="$SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_LABEL=$(security find-identity -v -p codesigning 2>/dev/null \
                 | grep "$SIGN_IDENTITY" \
                 | head -1 \
                 | sed -E 's/.*"([^"]+)".*/\1/')
fi

for arg in "$@"; do
  case "$arg" in
    --release)    CONFIG="release" ;;
    --debug)      CONFIG="debug" ;;
    --no-install) DO_INSTALL=0 ;;
    --no-run)     DO_RUN=0 ;;
    --clean)      DO_CLEAN=1 ;;
    --help|-h)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unbekanntes Flag: $arg"; exit 1 ;;
  esac
done

if [ "$DO_CLEAN" = "1" ]; then
  echo "[1/6] Clean: .build entfernen..."
  swift package clean
fi

echo "[2/6] swift build ($CONFIG)..."
if [ "$CONFIG" = "release" ]; then
  swift build -c release
  BUILD_DIR="$(swift build -c release --show-bin-path)"
else
  swift build
  BUILD_DIR="$(swift build --show-bin-path)"
fi

APP="$BUILD_DIR/NeoQuill.app"
BIN="$BUILD_DIR/NeoQuill"

if [ ! -x "$BIN" ]; then
  echo "FEHLER: Binary nicht gefunden: $BIN"
  exit 1
fi

echo "[3/6] Bundle zusammenbauen..."
if [ -e "$APP" ]; then
  mv "$APP" "/tmp/neoquill-old-$(date +%s)" 2>/dev/null || true
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NeoQuill"
cp Resources/Info.plist "$APP/Contents/Info.plist"

APP_VERSION="${NEOQUILL_VERSION:-$(tr -d '[:space:]' < "$VERSION_FILE")}"
BUILD_NUMBER="${NEOQUILL_BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || date -u +%Y%m%d%H%M)}"
GIT_COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
GIT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
if git diff --quiet --ignore-submodules -- && git diff --cached --quiet --ignore-submodules --; then
  GIT_DIRTY="clean"
else
  GIT_DIRTY="dirty"
fi
BUILD_DATE="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

plist_set_string() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Set :$key $value" "$APP/Contents/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :$key string $value" "$APP/Contents/Info.plist" >/dev/null
}

echo "[4/6] Version metadata: v$APP_VERSION build $BUILD_NUMBER ($GIT_BRANCH@$GIT_COMMIT, $GIT_DIRTY)"
plist_set_string "CFBundleShortVersionString" "$APP_VERSION"
plist_set_string "CFBundleVersion" "$BUILD_NUMBER"
plist_set_string "NeoQuillGitCommit" "$GIT_COMMIT"
plist_set_string "NeoQuillGitBranch" "$GIT_BRANCH"
plist_set_string "NeoQuillGitDirty" "$GIT_DIRTY"
plist_set_string "NeoQuillBuildDate" "$BUILD_DATE"

# SPM Resource Bundle (Fonts + AppIcon)
if [ -e "$BUILD_DIR/NeoQuill_NeoQuill.bundle" ]; then
  cp -R "$BUILD_DIR/NeoQuill_NeoQuill.bundle" "$APP/Contents/Resources/"
fi

# AppIcon direkt im Bundle (für Finder/Dock)
cp Sources/NeoQuill/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "[5/6] Code signing (ad-hoc — keine Apple Dev Cert in Keychain)..."
  echo "  → App läuft lokal. Für Distribution: \$NEOQUILL_SIGN_IDENTITY mit Apple Dev Cert setzen."
  codesign --force --deep --sign - "$APP" 2>&1 | tail -1
else
  echo "[5/6] Code signing mit \"$SIGN_LABEL\"..."
  codesign --force --deep --options=runtime \
    --entitlements "$ENTITLEMENTS" \
    --sign "$SIGN_IDENTITY" \
    "$APP" 2>&1 | tail -1
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  codesign --verify "$APP" && echo "  Signature OK (ad-hoc)"
else
  codesign --verify --deep --strict "$APP" && echo "  Signature OK"
fi

if [ "$DO_INSTALL" = "1" ]; then
  echo "[6/6] Install nach /Applications..."
  pkill -9 -f "Applications/NeoQuill" 2>/dev/null || true
  sleep 1
  if [ -e /Applications/NeoQuill.app ]; then
    mv /Applications/NeoQuill.app "$HOME/.Trash/NeoQuill.app.bak.$(date +%s)"
  fi
  ditto "$APP" /Applications/NeoQuill.app

  # macOS Dock + Finder zwingen, das neue App-Icon zu lesen (IconServices cached aggressiv)
  touch /Applications/NeoQuill.app
  find "$HOME/Library/Caches/com.apple.iconservices.store" -type f -delete 2>/dev/null || true
  killall Dock 2>/dev/null || true
  killall Finder 2>/dev/null || true

  if [ "$DO_RUN" = "1" ]; then
    open /Applications/NeoQuill.app
    sleep 2
    PID="$(pgrep -f "Applications/NeoQuill" 2>/dev/null | head -1 || true)"
    if [ -n "$PID" ]; then
      echo "  NeoQuill läuft, PID $PID"
    else
      echo "  NeoQuill gestartet"
    fi
  fi
else
  echo "[6/6] Install übersprungen (--no-install)"
  echo "  Bundle: $APP"
fi

echo ""
echo "Fertig."
