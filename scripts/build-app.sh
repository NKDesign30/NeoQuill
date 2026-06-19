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
# 2. Release: Developer ID Application bevorzugen
# 3. Debug: Apple Development bevorzugen
# 4. Fallback: ad-hoc ("-")
detect_sign_identity() {
  if [ -n "${NEOQUILL_SIGN_IDENTITY:-}" ]; then
    echo "$NEOQUILL_SIGN_IDENTITY"
    return
  fi
  local certs
  certs=$(security find-identity -v -p codesigning 2>/dev/null \
            | grep -E 'Apple Development|Developer ID Application' || true)

  if [ "$CONFIG" = "release" ]; then
    local developer_id
    developer_id=$(echo "$certs" | grep -i "Developer ID Application" | head -1 | awk '{print $2}' || true)
    if [ -n "$developer_id" ]; then
      echo "$developer_id"
      return
    fi
  fi

  # Prefer a development cert whose email matches NEOQUILL_PREFERRED_DEV_EMAIL
  # (for contributors with multiple Apple Developer identities in their Keychain).
  local preferred_development=""
  if [ -n "${NEOQUILL_PREFERRED_DEV_EMAIL:-}" ]; then
    preferred_development=$(echo "$certs" | grep -i "Apple Development" | grep -i "$NEOQUILL_PREFERRED_DEV_EMAIL" | head -1 | awk '{print $2}' || true)
  fi
  if [ -z "$preferred_development" ]; then
    preferred_development=$(echo "$certs" | grep -i "Apple Development" | head -1 | awk '{print $2}' || true)
  fi
  if [ -n "$preferred_development" ]; then
    echo "$preferred_development"
    return
  fi

  local fallback
  fallback=$(echo "$certs" | head -1 | awk '{print $2}' || true)
  if [ -n "$fallback" ]; then
    echo "$fallback"
  else
    echo "-"
  fi
}

resolve_existing_path() {
  local path="$1"
  while [ -L "$path" ]; do
    local target
    target="$(readlink "$path")"
    if [[ "$target" = /* ]]; then
      path="$target"
    else
      path="$(dirname "$path")/$target"
    fi
  done
  local dir
  dir="$(cd "$(dirname "$path")" && pwd -P)"
  printf '%s/%s\n' "$dir" "$(basename "$path")"
}

find_executable() {
  local name="$1"
  local override="${2:-}"
  if [ -n "$override" ] && [ -x "$override" ]; then
    resolve_existing_path "$override"
    return
  fi
  local found
  found="$(command -v "$name" 2>/dev/null || true)"
  if [ -n "$found" ] && [ -x "$found" ]; then
    resolve_existing_path "$found"
  fi
  return 0
}

runtime_asset_required() {
  [ "$CONFIG" = "release" ] || [ "${NEOQUILL_REQUIRE_RUNTIME_ASSETS:-0}" = "1" ]
}

copy_required_file() {
  local source="$1"
  local target="$2"
  local label="$3"

  if [ -f "$source" ]; then
    mkdir -p "$(dirname "$target")"
    ditto "$source" "$target"
    chmod u+w "$target" 2>/dev/null || true
    return
  fi

  if runtime_asset_required; then
    echo "FEHLER: $label fehlt: $source"
    exit 1
  fi
  echo "  WARNUNG: $label fehlt, Runtime-Asset wird nicht gebundelt: $source"
}

install_name_change_if_present() {
  local old="$1"
  local new="$2"
  local binary="$3"

  if otool -L "$binary" 2>/dev/null | grep -Fq "$old"; then
    install_name_tool -change "$old" "$new" "$binary"
  fi
}

sign_nested_runtime_file() {
  local binary="$1"
  if [ "$SIGN_IDENTITY" = "-" ]; then
    codesign --force --sign - "$binary" >/dev/null
  elif [ "$IS_DEVELOPER_ID" = "1" ]; then
    codesign --force --timestamp --options=runtime --sign "$SIGN_IDENTITY" "$binary" >/dev/null
  else
    codesign --force --options=runtime --sign "$SIGN_IDENTITY" "$binary" >/dev/null
  fi
}

copy_ggml_backend_plugins() {
  local source_dir="${NEOQUILL_GGML_BACKEND_DIR:-/opt/homebrew/opt/ggml/libexec}"
  local backend_dir="$APP/Contents/MacOS"

  if [ ! -d "$source_dir" ]; then
    if runtime_asset_required; then
      echo "FEHLER: GGML Backend-Plugin-Ordner fehlt: $source_dir"
      exit 1
    fi
    echo "  WARNUNG: GGML Backend-Plugin-Ordner fehlt: $source_dir"
    return
  fi

  mkdir -p "$backend_dir"
  local copied=0
  local plugin
  for plugin in "$source_dir"/libggml-*.so; do
    [ -f "$plugin" ] || continue
    ditto "$plugin" "$backend_dir/$(basename "$plugin")"
    chmod 755 "$backend_dir/$(basename "$plugin")"
    copied=1
  done

  if [ "$copied" != "1" ]; then
    if runtime_asset_required; then
      echo "FEHLER: Keine GGML Backend-Plugins in $source_dir gefunden."
      exit 1
    fi
    echo "  WARNUNG: Keine GGML Backend-Plugins in $source_dir gefunden."
    return
  fi

  for plugin in "$backend_dir"/libggml-*.so; do
    install_name_tool -add_rpath "@loader_path/../Frameworks" "$plugin" 2>/dev/null || true
    install_name_change_if_present "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" "$plugin"
    install_name_change_if_present "/usr/local/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" "$plugin"
    install_name_change_if_present "/opt/homebrew/opt/libomp/lib/libomp.dylib" "@rpath/libomp.dylib" "$plugin"
    install_name_change_if_present "/usr/local/opt/libomp/lib/libomp.dylib" "@rpath/libomp.dylib" "$plugin"
    sign_nested_runtime_file "$plugin"
  done
}

bundle_whisper_runtime_assets() {
  local models_dir="$APP/Contents/Resources/Models"
  local frameworks_dir="$APP/Contents/Frameworks"
  local cli_target="$APP/Contents/MacOS/whisper-cli"
  local model_source="${NEOQUILL_WHISPER_MODEL_PATH:-$HOME/.cache/whisper-cpp/ggml-large-v3-turbo.bin}"
  local cli_source
  cli_source="$(find_executable whisper-cli "${NEOQUILL_WHISPER_CLI_PATH:-}")"

  echo "[4.5/6] Whisper large-v3-turbo Runtime bundeln..."
  copy_required_file "$model_source" "$models_dir/ggml-large-v3-turbo.bin" "Whisper large-v3-turbo Modell"
  if [ ! -f "$models_dir/ggml-large-v3-turbo.bin" ]; then
    echo "  WARNUNG: Whisper-Runtime wird ohne Modell nicht gebundelt."
    return
  fi

  if [ -n "$cli_source" ]; then
    copy_required_file "$cli_source" "$cli_target" "whisper-cli"
    chmod 755 "$cli_target"
  elif runtime_asset_required; then
    echo "FEHLER: whisper-cli fehlt. Installiere whisper.cpp oder setze NEOQUILL_WHISPER_CLI_PATH."
    exit 1
  else
    echo "  WARNUNG: whisper-cli fehlt, Final-STT nutzt später WhisperKit-Fallback."
    return
  fi

  copy_required_file "${NEOQUILL_LIBWHISPER_PATH:-/opt/homebrew/opt/whisper-cpp/lib/libwhisper.1.dylib}" "$frameworks_dir/libwhisper.1.dylib" "libwhisper.1.dylib"
  copy_required_file "${NEOQUILL_LIBGGML_PATH:-/opt/homebrew/opt/ggml/lib/libggml.0.dylib}" "$frameworks_dir/libggml.0.dylib" "libggml.0.dylib"
  copy_required_file "${NEOQUILL_LIBGGML_BASE_PATH:-/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib}" "$frameworks_dir/libggml-base.0.dylib" "libggml-base.0.dylib"
  copy_required_file "${NEOQUILL_LIBOMP_PATH:-/opt/homebrew/opt/libomp/lib/libomp.dylib}" "$frameworks_dir/libomp.dylib" "libomp.dylib"

  if [ ! -f "$frameworks_dir/libwhisper.1.dylib" ] \
     || [ ! -f "$frameworks_dir/libggml.0.dylib" ] \
     || [ ! -f "$frameworks_dir/libggml-base.0.dylib" ] \
     || [ ! -f "$frameworks_dir/libomp.dylib" ]; then
    echo "  WARNUNG: whisper-cli wurde gefunden, aber nicht alle dylibs. Final-STT wird nicht gebundelt."
    rm -f "$cli_target" \
      "$frameworks_dir/libwhisper.1.dylib" \
      "$frameworks_dir/libggml.0.dylib" \
      "$frameworks_dir/libggml-base.0.dylib" \
      "$frameworks_dir/libomp.dylib"
    return
  fi

  install_name_tool -add_rpath "@executable_path/../Frameworks" "$cli_target" 2>/dev/null || true

  install_name_tool -id "@rpath/libwhisper.1.dylib" "$frameworks_dir/libwhisper.1.dylib"
  install_name_tool -id "@rpath/libggml.0.dylib" "$frameworks_dir/libggml.0.dylib"
  install_name_tool -id "@rpath/libggml-base.0.dylib" "$frameworks_dir/libggml-base.0.dylib"
  install_name_tool -id "@rpath/libomp.dylib" "$frameworks_dir/libomp.dylib"

  copy_ggml_backend_plugins

  for binary in "$cli_target" "$frameworks_dir/libwhisper.1.dylib"; do
    install_name_change_if_present "/opt/homebrew/opt/ggml/lib/libggml.0.dylib" "@rpath/libggml.0.dylib" "$binary"
    install_name_change_if_present "/opt/homebrew/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" "$binary"
    install_name_change_if_present "/usr/local/opt/ggml/lib/libggml.0.dylib" "@rpath/libggml.0.dylib" "$binary"
    install_name_change_if_present "/usr/local/opt/ggml/lib/libggml-base.0.dylib" "@rpath/libggml-base.0.dylib" "$binary"
  done
  install_name_change_if_present "/opt/homebrew/opt/whisper-cpp/lib/libwhisper.1.dylib" "@rpath/libwhisper.1.dylib" "$cli_target"
  install_name_change_if_present "/usr/local/opt/whisper-cpp/lib/libwhisper.1.dylib" "@rpath/libwhisper.1.dylib" "$cli_target"
  install_name_change_if_present "/opt/homebrew/opt/libomp/lib/libomp.dylib" "@rpath/libomp.dylib" "$frameworks_dir/libggml-base.0.dylib"
  install_name_change_if_present "/usr/local/opt/libomp/lib/libomp.dylib" "@rpath/libomp.dylib" "$frameworks_dir/libggml-base.0.dylib"

  echo "  Whisper Runtime OK: $(du -h "$models_dir/ggml-large-v3-turbo.bin" | awk '{print $1}') Modell + gebundeltes whisper-cli"
}

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

SIGN_IDENTITY=$(detect_sign_identity)
SIGN_LABEL="$SIGN_IDENTITY"
if [ "$SIGN_IDENTITY" != "-" ]; then
  SIGN_LABEL=$(security find-identity -v -p codesigning 2>/dev/null \
                 | grep "$SIGN_IDENTITY" \
                 | head -1 \
                 | sed -E 's/.*"([^"]+)".*/\1/')
fi
IS_DEVELOPER_ID=0
if [[ "$SIGN_LABEL" == Developer\ ID\ Application:* ]]; then
  IS_DEVELOPER_ID=1
fi

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
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
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

if [ -d "$BUILD_DIR/Sparkle.framework" ]; then
  ditto "$BUILD_DIR/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
  if ! otool -l "$APP/Contents/MacOS/NeoQuill" | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/NeoQuill"
  fi
fi

# AppIcon direkt im Bundle (für Finder/Dock)
cp Sources/NeoQuill/Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns" 2>/dev/null || true

bundle_whisper_runtime_assets

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "[5/6] Code signing (ad-hoc — keine Apple Dev Cert in Keychain)..."
  echo "  → App läuft lokal. Für Distribution: \$NEOQUILL_SIGN_IDENTITY mit Apple Dev Cert setzen."
  codesign --force --deep --sign - "$APP" 2>&1 | tail -1
else
  echo "[5/6] Code signing mit \"$SIGN_LABEL\"..."
  if [ "$IS_DEVELOPER_ID" = "1" ]; then
    codesign --force --deep --timestamp --options=runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$APP" 2>&1 | tail -1
  else
    codesign --force --deep --options=runtime \
      --entitlements "$ENTITLEMENTS" \
      --sign "$SIGN_IDENTITY" \
      "$APP" 2>&1 | tail -1
  fi
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
      echo "FEHLER: NeoQuill wurde gestartet, aber kein laufender Prozess gefunden."
      exit 1
    fi
  fi
else
  echo "[6/6] Install übersprungen (--no-install)"
  echo "  Bundle: $APP"
fi

echo ""
echo "Fertig."
