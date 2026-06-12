#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT="$ROOT_DIR/WallFlow.xcodeproj"
SCHEME="WallFlow"
CONFIGURATION="${CONFIGURATION:-Release}"
DESTINATION="${DESTINATION:-generic/platform=macOS}"
DERIVED_DATA_PATH="$ROOT_DIR/.DerivedData"
DIST_DIR="$ROOT_DIR/dist"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
NOTARY_PROFILE="${NOTARY_PROFILE:-WallFlow-notary}"
TEAM_ID="${TEAM_ID:-}"
SKIP_NOTARIZE="${SKIP_NOTARIZE:-0}"

if ! security find-identity -v -p codesigning | grep -F "$SIGNING_IDENTITY" >/dev/null; then
  cat >&2 <<EOF
Developer ID signing identity was not found.

Expected identity:
  $SIGNING_IDENTITY

Install a "Developer ID Application" certificate in Keychain Access, or pass
SIGNING_IDENTITY="Developer ID Application: Name (TEAMID)".
EOF
  exit 1
fi

VERSION="$(
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    -showBuildSettings 2>/dev/null |
    awk -F '= ' '/MARKETING_VERSION/ { print $2; exit }'
)"

if [[ -z "$VERSION" ]]; then
  echo "Could not determine MARKETING_VERSION." >&2
  exit 1
fi

BUILD_ARGS=(
  -project "$PROJECT"
  -scheme "$SCHEME"
  -configuration "$CONFIGURATION"
  -derivedDataPath "$DERIVED_DATA_PATH"
  -destination "$DESTINATION"
  CODE_SIGN_STYLE=Manual
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  OTHER_CODE_SIGN_FLAGS=--timestamp
)

if [[ -n "$TEAM_ID" ]]; then
  BUILD_ARGS+=(DEVELOPMENT_TEAM="$TEAM_ID")
fi

xcodebuild "${BUILD_ARGS[@]}" clean build

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/WallFlow.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "App not found: $APP_PATH" >&2
  exit 1
fi

codesign --verify --strict --deep --verbose=2 "$APP_PATH"

DMG_PATH="$(
  APP_PATH="$APP_PATH" \
  CONFIGURATION="$CONFIGURATION" \
  VERSION="$VERSION" \
  "$ROOT_DIR/scripts/make-dmg.sh" |
  tail -n 1
)"

codesign --force --sign "$SIGNING_IDENTITY" --timestamp "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" == "1" ]]; then
  echo "Skipping notarization because SKIP_NOTARIZE=1."
else
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl -a -t open --context context:primary-signature -vvv "$DMG_PATH"
fi

shasum -a 256 "$DMG_PATH" | tee "$DIST_DIR/WallFlow-$VERSION.dmg.sha256"
echo "$DMG_PATH"
