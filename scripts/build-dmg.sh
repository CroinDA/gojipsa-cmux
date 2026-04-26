#!/usr/bin/env bash
# build-dmg.sh — Create distributable .dmg from GOJIPSA.app
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.0}"
APP_NAME="GOJIPSA"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING="$DIST_DIR/dmg-staging"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "❌ VERSION must be semver (got: '$VERSION')" >&2
    exit 1
fi
case "$STAGING" in
    "$PROJECT_DIR/dist/"*) ;;
    *) echo "❌ Refusing to operate outside dist/" >&2; exit 1 ;;
esac

if [ ! -d "$APP_DIR" ]; then
    echo "❌ $APP_DIR not found. Run scripts/build-app.sh first." >&2
    exit 1
fi

echo "📀 Preparing DMG staging..."
rm -rf "$STAGING" "$DMG_PATH"
mkdir -p "$STAGING"
cp -R "$APP_DIR" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

echo "💾 Building $DMG_NAME..."
hdiutil create -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    -fs HFS+ \
    "$DMG_PATH" 2>&1 | tail -5

# Sign the DMG too
SIGN_ID="${SIGN_ID:-CroinDA HQ Development}"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --sign "$SIGN_ID" "$DMG_PATH" 2>&1 | tail -3
    echo "  DMG signed."
fi

rm -rf "$STAGING"

echo ""
echo "✅ DMG: $DMG_PATH"
echo "   Size: $(du -sh "$DMG_PATH" | cut -f1)"
echo "   SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
