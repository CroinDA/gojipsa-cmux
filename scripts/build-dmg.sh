#!/usr/bin/env bash
# Create the distributable GOJIPSA DMG from the Xcode-built app bundle.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="GOJIPSA"
VERSION="${VERSION:-2.0.4}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
DMG_SIGNED=0

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

[ -d "$APP_DIR" ] || fail "$APP_DIR not found. Run scripts/build-app.sh first."

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
APP_SIGN_INFO="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"

STAGING="$(mktemp -d "${TMPDIR:-/tmp}/gojipsa-dmg.XXXXXX")"
cleanup() {
    rm -rf "$STAGING"
}
trap cleanup EXIT

rm -f "$DMG_PATH"
mkdir -p "$DIST_DIR"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "Creating $DMG_PATH..."
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -fs HFS+ \
    "$DMG_PATH"

SIGN_ID="$(printf '%s\n' "$APP_SIGN_INFO" | awk -F= '/^Authority=Developer ID Application:/ { print $2; exit }')"
if [ -n "$SIGN_ID" ] && security find-identity -v -p codesigning | grep -Fq "$SIGN_ID"; then
    echo "Signing DMG with $SIGN_ID..."
    codesign --force --sign "$SIGN_ID" "$DMG_PATH"
    codesign --verify --verbose=2 "$DMG_PATH"
    DMG_SIGNED=1
else
    echo "Skipping DMG signing; no matching local Developer ID private key is available."
fi

echo ""
echo "DMG: $DMG_PATH"
echo "Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo "SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo "Developer ID signed DMG: $DMG_SIGNED"
