#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/WallFlow.xcodeproj"
SCHEME="WallFlow"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
DIST_DIR="$ROOT_DIR/dist"
DMG_ROOT="$DIST_DIR/dmgroot"

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
  VERSION="$(
    xcodebuild \
      -project "$PROJECT" \
      -scheme "$SCHEME" \
      -configuration "$CONFIGURATION" \
      -derivedDataPath "$DERIVED_DATA_PATH" \
      -showBuildSettings 2>/dev/null |
      awk -F '= ' '/MARKETING_VERSION/ { print $2; exit }'
  )"
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(
    awk -F '= ' '/MARKETING_VERSION/ { gsub(/;/, "", $2); print $2; exit }' \
      "$PROJECT/project.pbxproj"
  )"
fi

if [[ -z "$VERSION" ]]; then
  echo "Could not determine MARKETING_VERSION." >&2
  exit 1
fi

APP_PATH_WAS_PROVIDED="${APP_PATH+x}"
APP_PATH="${APP_PATH:-$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/WallFlow.app}"
DMG_PATH="$DIST_DIR/WallFlow-$VERSION.dmg"

mkdir -p "$DIST_DIR"

cleanup() {
  rm -rf "$DMG_ROOT"
}
trap cleanup EXIT

if [[ -z "$APP_PATH_WAS_PROVIDED" ]]; then
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -destination "$DESTINATION" \
    build
fi

if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  echo "Pass APP_PATH=/path/to/WallFlow.app if you exported a signed app from Xcode." >&2
  exit 1
fi

mkdir -p "$DMG_ROOT"
cp -R "$APP_PATH" "$DMG_ROOT/"

rm -f "$DMG_PATH"

create_simple_dmg() {
  ln -s /Applications "$DMG_ROOT/Applications"
  local temp_dmg="$DIST_DIR/WallFlow-$VERSION.simple.dmg"
  rm -f "$temp_dmg"
  hdiutil makehybrid \
    -default-volume-name "WallFlow" \
    -hfs \
    -o "$temp_dmg" \
    "$DMG_ROOT"
  hdiutil convert \
    "$temp_dmg" \
    -format UDZO \
    -ov \
    -o "$DMG_PATH"
  rm -f "$temp_dmg"
}

if command -v create-dmg >/dev/null 2>&1; then
  if ! create-dmg \
    --volname "WallFlow" \
    --window-size 520 320 \
    --icon-size 96 \
    --icon "WallFlow.app" 150 155 \
    --app-drop-link 370 155 \
    --no-internet-enable \
    --sandbox-safe \
    --skip-jenkins \
    "$DMG_PATH" \
    "$DMG_ROOT"; then
    echo "create-dmg failed; creating a simple DMG instead." >&2
    rm -f "$DMG_PATH"
    create_simple_dmg
  fi
else
  create_simple_dmg
fi

echo "$DMG_PATH"
