#!/usr/bin/env bash
# build-dmg.sh - Create and sign the distributable GOJIPSA DMG.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.4}"
SIGNING_MODE="${SIGNING_MODE:-manual}"
APP_NAME="GOJIPSA"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/dmg-staging"
DMG_SIGNED=0

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

if [ "$SIGNING_MODE" != "manual" ] && [ "$SIGNING_MODE" != "xcode-auto" ]; then
    fail "SIGNING_MODE must be 'manual' or 'xcode-auto' (got: '$SIGNING_MODE')"
fi

case "$STAGING" in
    "$PROJECT_DIR/dist/"*) ;;
    *) fail "Refusing to operate outside dist/" ;;
esac

if [ ! -d "$APP_DIR" ]; then
    fail "$APP_DIR not found. Run scripts/build-app.sh first."
fi

APP_SIGN_INFO="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"
echo "$APP_SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "$APP_DIR is not Developer ID signed"
echo "$APP_SIGN_INFO" | grep -q "flags=.*runtime" || fail "$APP_DIR is missing Hardened Runtime"

if [ -z "${SIGN_ID:-}" ]; then
    if [ "$SIGNING_MODE" = "xcode-auto" ]; then
        SIGN_ID="$(printf '%s\n' "$APP_SIGN_INFO" | awk -F= '/^Authority=Developer ID Application:/ { print $2; exit }')"
        if [ -z "$SIGN_ID" ]; then
            fail "Could not infer Developer ID identity from $APP_DIR"
        fi
    else
        fail "SIGN_ID is required. Use: SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" $0"
    fi
fi

if [[ "$SIGN_ID" != Developer\ ID\ Application:* ]]; then
    fail "SIGN_ID must be a Developer ID Application identity (got: '$SIGN_ID')"
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_ID"; then
    if [ "$SIGNING_MODE" = "xcode-auto" ]; then
        echo "Developer ID identity is not available as a local private key: $SIGN_ID"
        echo "Continuing with an unsigned DMG that contains the stapled Developer ID app."
        SIGN_ID=""
    else
        fail "Code signing identity not found in keychain: $SIGN_ID"
    fi
fi

if [ "$SIGNING_MODE" = "xcode-auto" ]; then
    xcrun stapler validate "$APP_DIR"
fi

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

if [ -n "$SIGN_ID" ]; then
    echo "Signing DMG..."
    codesign --force --sign "$SIGN_ID" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"

    DMG_SIGN_INFO="$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1)"
    echo "$DMG_SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "$DMG_PATH is not Developer ID signed"
    DMG_SIGNED=1
else
    echo "Skipping DMG signing; no local Developer ID private key is installed."
fi

echo ""
echo "DMG: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo "SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo "Developer ID signed DMG: $DMG_SIGNED"
