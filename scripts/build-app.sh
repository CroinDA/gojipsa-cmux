#!/usr/bin/env bash
# build-app.sh - Archive and export a signed universal GOJIPSA.app.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
APP_NAME="GOJIPSA"
PROJECT_NAME="GOJIPSA"
SCHEME="GOJIPSA"
TEAM_ID="${DEVELOPMENT_TEAM:-3BAL9BR86N}"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/$APP_NAME.xcarchive"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DERIVED_DATA="$PROJECT_DIR/.build/xcode-derived-data"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

case "$APP_DIR" in
    "$PROJECT_DIR/dist/"*) ;;
    *) fail "Refusing to operate outside dist/" ;;
esac

if [ ! -d "$PROJECT_NAME.xcodeproj" ]; then
    fail "$PROJECT_NAME.xcodeproj not found"
fi

if [ -z "${SIGN_ID:-}" ]; then
    fail "SIGN_ID is required. Use: SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" $0"
fi

if [[ "$SIGN_ID" != Developer\ ID\ Application:* ]]; then
    fail "SIGN_ID must be a Developer ID Application identity (got: '$SIGN_ID')"
fi

if ! security find-identity -v -p codesigning | grep -Fq "$SIGN_ID"; then
    fail "Code signing identity not found in keychain: $SIGN_ID"
fi

echo "Building signed Release archive..."
rm -rf "$ARCHIVE_PATH" "$APP_DIR"
mkdir -p "$DIST_DIR"

xcodebuild \
    -project "$PROJECT_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE_PATH" \
    -derivedDataPath "$DERIVED_DATA" \
    clean archive \
    MARKETING_VERSION="$VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="$SIGN_ID" \
    CODE_SIGNING_ALLOWED=YES \
    CODE_SIGNING_REQUIRED=YES \
    ENABLE_HARDENED_RUNTIME=YES \
    ONLY_ACTIVE_ARCH=NO \
    ARCHS="arm64 x86_64"

BUILT_APP="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
if [ ! -d "$BUILT_APP" ]; then
    fail "Archived app not found at $BUILT_APP"
fi

echo "Copying app to dist..."
cp -R "$BUILT_APP" "$APP_DIR"

BINARY="$APP_DIR/Contents/MacOS/$APP_NAME"
if [ ! -x "$BINARY" ]; then
    fail "App binary not found or not executable: $BINARY"
fi

ARCHS_OUT="$(lipo -archs "$BINARY")"
case " $ARCHS_OUT " in
    *" arm64 "*" x86_64 "*) ;;
    *) fail "Expected universal binary with arm64 and x86_64, got: $ARCHS_OUT" ;;
esac

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
SIGN_INFO="$(codesign -dv --verbose=4 "$APP_DIR" 2>&1)"

echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "App is not signed with Developer ID Application"
echo "$SIGN_INFO" | grep -q "flags=.*runtime" || fail "App is missing Hardened Runtime"
echo "$SIGN_INFO" | grep -q "TeamIdentifier=" || fail "App signature is missing TeamIdentifier"

echo ""
echo "Built: $APP_DIR"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Architectures: $ARCHS_OUT"
echo "Size: $(du -sh "$APP_DIR" | cut -f1)"
