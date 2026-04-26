#!/usr/bin/env bash
# build-dmg.sh - Create and sign the distributable GOJIPSA DMG.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.1}"
APP_NAME="GOJIPSA"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/dmg-staging"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

case "$STAGING" in
    "$PROJECT_DIR/dist/"*) ;;
    *) fail "Refusing to operate outside dist/" ;;
esac

if [ -z "${SIGN_ID:-}" ]; then
    fail "SIGN_ID is required. Use: SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" $0"
fi

if [[ "$SIGN_ID" != Developer\ ID\ Application:* ]]; then
    fail "SIGN_ID must be a Developer ID Application identity (got: '$SIGN_ID')"
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_ID"; then
    fail "Code signing identity not found in keychain: $SIGN_ID"
fi

if [ ! -d "$APP_DIR" ]; then
    fail "$APP_DIR not found. Run scripts/build-app.sh first."
fi

APP_SIGN_INFO="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
echo "$APP_SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "$APP_DIR is not Developer ID signed"
echo "$APP_SIGN_INFO" | grep -q "flags=.*runtime" || fail "$APP_DIR is missing Hardened Runtime"

cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

echo "Preparing DMG staging..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Building $DMG_NAME..."
hdiutil create -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

echo "Signing DMG..."
codesign --force --sign "$SIGN_ID" "$DMG_PATH"
codesign --verify --verbose=2 "$DMG_PATH"

DMG_SIGN_INFO="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"
echo "$DMG_SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "$DMG_PATH is not Developer ID signed"

echo ""
echo "DMG: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo "SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
