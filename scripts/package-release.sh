#!/usr/bin/env bash
# Buildet ein reproduzierbares NeoQuill-Release-Artefakt mit Bundle-Metadaten,
# Signaturcheck, ZIP und SHA256-Manifest.

set -euo pipefail

cd "$(dirname "$0")/.."

ALLOW_DIRTY=0
CLEAN_BUILD=0
LAUNCH_SMOKE=0
STRICT_DISTRIBUTION=0
DIST_DIR="dist"

usage() {
  cat <<'USAGE'
NeoQuill Release Packaging
Buildet ein reproduzierbares Release-Artefakt mit Bundle-Metadaten,
Signaturcheck, ZIP und SHA256-Manifest.

Usage:
  ./scripts/package-release.sh
  ./scripts/package-release.sh --clean
  ./scripts/package-release.sh --allow-dirty
  ./scripts/package-release.sh --launch-smoke
  ./scripts/package-release.sh --strict-distribution
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --allow-dirty)          ALLOW_DIRTY=1 ;;
    --clean)                CLEAN_BUILD=1 ;;
    --launch-smoke)         LAUNCH_SMOKE=1 ;;
    --strict-distribution)  STRICT_DISTRIBUTION=1 ;;
    --help|-h)
      usage
      exit 0
      ;;
    *) echo "Unbekanntes Flag: $arg"; exit 1 ;;
  esac
done

if ! command -v swift >/dev/null 2>&1; then
  echo "FEHLER: swift ist nicht auf PATH."
  exit 1
fi

BUILD_ARGS=(--release --no-install --no-run)
if [ "$CLEAN_BUILD" = "1" ]; then
  BUILD_ARGS+=(--clean)
fi

echo "[1/5] Release-Bundle bauen..."
./scripts/build-app.sh "${BUILD_ARGS[@]}"

BUILD_DIR="$(swift build -c release --show-bin-path)"
APP="$BUILD_DIR/NeoQuill.app"
INFO_PLIST="$APP/Contents/Info.plist"

if [ ! -d "$APP" ]; then
  echo "FEHLER: App-Bundle nicht gefunden: $APP"
  exit 1
fi

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$INFO_PLIST"
}

VERSION_FILE_VALUE="$(tr -d '[:space:]' < VERSION)"
BUNDLE_VERSION="$(plist_value CFBundleShortVersionString)"
BUILD_NUMBER="$(plist_value CFBundleVersion)"
GIT_COMMIT="$(plist_value NeoQuillGitCommit)"
GIT_BRANCH="$(plist_value NeoQuillGitBranch)"
GIT_DIRTY="$(plist_value NeoQuillGitDirty)"
BUILD_DATE="$(plist_value NeoQuillBuildDate)"

echo "[2/5] Bundle-Metadaten prüfen..."
if [ "$BUNDLE_VERSION" != "$VERSION_FILE_VALUE" ]; then
  echo "FEHLER: VERSION=$VERSION_FILE_VALUE, Bundle=$BUNDLE_VERSION"
  exit 1
fi

if [ "$GIT_DIRTY" != "clean" ] && [ "$ALLOW_DIRTY" != "1" ]; then
  echo "FEHLER: Git-Stand ist dirty. Für Testläufe: --allow-dirty, für Release erst committen."
  exit 1
fi

echo "  v$BUNDLE_VERSION build $BUILD_NUMBER ($GIT_BRANCH@$GIT_COMMIT, $GIT_DIRTY)"

echo "[3/5] Signatur prüfen..."
codesign --verify --deep --strict "$APP"
SIGNING_AUTHORITY="$(codesign -dv --verbose=4 "$APP" 2>&1 | sed -n 's/^Authority=//p' | head -1 || true)"
if [ -z "$SIGNING_AUTHORITY" ]; then
  SIGNING_AUTHORITY="ad-hoc"
fi

if [[ "$SIGNING_AUTHORITY" != Developer\ ID\ Application:* ]]; then
  MESSAGE="WARNUNG: Signatur ist '$SIGNING_AUTHORITY'. Für öffentliche Distribution Developer ID Application + Notarization nutzen."
  if [ "$STRICT_DISTRIBUTION" = "1" ]; then
    echo "FEHLER: $MESSAGE"
    exit 1
  fi
  echo "  $MESSAGE"
else
  echo "  Distribution-Signatur OK: $SIGNING_AUTHORITY"
fi

if [ "$LAUNCH_SMOKE" = "1" ]; then
  echo "[4/5] Launch-Smoke..."
  APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
  open -n "$APP_ABS"
  PID=""
  for _ in {1..30}; do
    PID="$(pgrep -f "$APP_ABS/Contents/MacOS/NeoQuill" | head -1 || true)"
    if [ -n "$PID" ]; then
      break
    fi
    sleep 0.5
  done

  if [ -z "$PID" ]; then
    echo "FEHLER: Launch-Smoke fand keinen laufenden NeoQuill-Prozess."
    exit 1
  fi

  echo "  Launch OK, PID $PID"
  kill "$PID" 2>/dev/null || true
  sleep 1
else
  echo "[4/5] Launch-Smoke übersprungen."
fi

echo "[5/5] Release-Artefakt schreiben..."
mkdir -p "$DIST_DIR"

DIRTY_SUFFIX=""
if [ "$GIT_DIRTY" != "clean" ]; then
  DIRTY_SUFFIX="-dirty"
fi

ARCHIVE_BASENAME="NeoQuill-v${BUNDLE_VERSION}-build${BUILD_NUMBER}-${GIT_COMMIT}${DIRTY_SUFFIX}"
ZIP_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.zip"
SHA_PATH="$ZIP_PATH.sha256"
MANIFEST_PATH="$DIST_DIR/${ARCHIVE_BASENAME}.json"

rm -f "$ZIP_PATH" "$SHA_PATH" "$MANIFEST_PATH"
ditto -c -k --keepParent "$APP" "$ZIP_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$(basename "$ZIP_PATH")") > "$SHA_PATH"
SHA256="$(awk '{print $1}' "$SHA_PATH")"

{
  printf '{\n'
  printf '  "app": "NeoQuill",\n'
  printf '  "version": "%s",\n' "$BUNDLE_VERSION"
  printf '  "build": "%s",\n' "$BUILD_NUMBER"
  printf '  "gitCommit": "%s",\n' "$GIT_COMMIT"
  printf '  "gitBranch": "%s",\n' "$GIT_BRANCH"
  printf '  "gitDirty": "%s",\n' "$GIT_DIRTY"
  printf '  "buildDate": "%s",\n' "$BUILD_DATE"
  printf '  "signingAuthority": "%s",\n' "$SIGNING_AUTHORITY"
  printf '  "archive": "%s",\n' "$(basename "$ZIP_PATH")"
  printf '  "sha256": "%s"\n' "$SHA256"
  printf '}\n'
} > "$MANIFEST_PATH"

echo ""
echo "Fertig:"
echo "  ZIP:      $ZIP_PATH"
echo "  SHA256:   $SHA_PATH"
echo "  Manifest: $MANIFEST_PATH"
