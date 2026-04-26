#!/usr/bin/env bash
# build-app.sh - Archive and export a signed universal GOJIPSA.app.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.1}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
SIGNING_MODE="${SIGNING_MODE:-manual}"
APP_NAME="GOJIPSA"
PROJECT_NAME="GOJIPSA"
SCHEME="GOJIPSA"
TEAM_ID="${DEVELOPMENT_TEAM:-3BAL9BR86N}"
DIST_DIR="$PROJECT_DIR/dist"
ARCHIVE_PATH="$DIST_DIR/$APP_NAME.xcarchive"
APP_DIR="$DIST_DIR/$APP_NAME.app"
DERIVED_DATA="$PROJECT_DIR/.build/xcode-derived-data"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$PROJECT_DIR/scripts/ExportOptions-developer-id-upload.plist}"
UPLOAD_EXPORT_DIR="$DIST_DIR/xcode-upload"
NOTARIZED_EXPORT_DIR="$DIST_DIR/xcode-notarized"
XCODE_NOTARY_TIMEOUT_SECONDS="${XCODE_NOTARY_TIMEOUT_SECONDS:-1800}"
XCODE_NOTARY_POLL_SECONDS="${XCODE_NOTARY_POLL_SECONDS:-60}"

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

if [ "$SIGNING_MODE" != "manual" ] && [ "$SIGNING_MODE" != "xcode-auto" ]; then
    fail "SIGNING_MODE must be 'manual' or 'xcode-auto' (got: '$SIGNING_MODE')"
fi

verify_developer_id_app() {
    local app_dir="$1"
    local binary="$app_dir/Contents/MacOS/$APP_NAME"

    if [ ! -x "$binary" ]; then
        fail "App binary not found or not executable: $binary"
    fi

    ARCHS_OUT="$(lipo -archs "$binary")"
    case " $ARCHS_OUT " in
        *" arm64 "*) ;;
        *) fail "Expected universal binary to include arm64, got: $ARCHS_OUT" ;;
    esac
    case " $ARCHS_OUT " in
        *" x86_64 "*) ;;
        *) fail "Expected universal binary to include x86_64, got: $ARCHS_OUT" ;;
    esac

    codesign --verify --deep --strict --verbose=2 "$app_dir"
    SIGN_INFO="$(codesign -dv --verbose=4 "$app_dir" 2>&1)"

    echo "$SIGN_INFO" | grep -q "Authority=Developer ID Application" || fail "App is not signed with Developer ID Application"
    echo "$SIGN_INFO" | grep -q "flags=.*runtime" || fail "App is missing Hardened Runtime"
    echo "$SIGN_INFO" | grep -q "TeamIdentifier=" || fail "App signature is missing TeamIdentifier"
}

build_manual() {
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

    local built_app="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
    if [ ! -d "$built_app" ]; then
        fail "Archived app not found at $built_app"
    fi

    echo "Copying app to dist..."
    ditto "$built_app" "$APP_DIR"
    verify_developer_id_app "$APP_DIR"
}

wait_for_xcode_notarized_export() {
    local deadline=$((SECONDS + XCODE_NOTARY_TIMEOUT_SECONDS))
    local export_log
    export_log="$(mktemp)"

    echo "Waiting for Xcode notarization and exporting notarized app..."
    while true; do
        rm -rf "$NOTARIZED_EXPORT_DIR"
        mkdir -p "$NOTARIZED_EXPORT_DIR"

        if xcodebuild \
            -exportNotarizedApp \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$NOTARIZED_EXPORT_DIR" >"$export_log" 2>&1; then
            rm -f "$export_log"
            break
        fi

        if [ "$SECONDS" -ge "$deadline" ]; then
            tail -100 "$export_log" >&2 || true
            rm -f "$export_log"
            fail "Timed out waiting for Xcode notarization export after ${XCODE_NOTARY_TIMEOUT_SECONDS}s"
        fi

        echo "Notarization is not ready yet; retrying in ${XCODE_NOTARY_POLL_SECONDS}s..."
        tail -20 "$export_log" || true
        sleep "$XCODE_NOTARY_POLL_SECONDS"
    done
}

build_xcode_auto() {
    if [ ! -f "$EXPORT_OPTIONS_PLIST" ]; then
        fail "Export options plist not found: $EXPORT_OPTIONS_PLIST"
    fi

    echo "Building Xcode-managed Developer ID Release archive..."
    rm -rf "$ARCHIVE_PATH" "$APP_DIR" "$UPLOAD_EXPORT_DIR" "$NOTARIZED_EXPORT_DIR"
    mkdir -p "$DIST_DIR" "$UPLOAD_EXPORT_DIR"

    xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -archivePath "$ARCHIVE_PATH" \
        -derivedDataPath "$DERIVED_DATA" \
        clean archive \
        -allowProvisioningUpdates \
        MARKETING_VERSION="$VERSION" \
        CURRENT_PROJECT_VERSION="$BUILD_NUMBER" \
        DEVELOPMENT_TEAM="$TEAM_ID" \
        CODE_SIGN_STYLE=Automatic \
        CODE_SIGNING_ALLOWED=YES \
        CODE_SIGNING_REQUIRED=YES \
        ENABLE_HARDENED_RUNTIME=YES \
        ONLY_ACTIVE_ARCH=NO \
        ARCHS="arm64 x86_64"

    local built_app="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
    if [ ! -d "$built_app" ]; then
        fail "Archived app not found at $built_app"
    fi

    echo "Uploading archive through Xcode for Developer ID notarization..."
    xcodebuild \
        -exportArchive \
        -archivePath "$ARCHIVE_PATH" \
        -exportPath "$UPLOAD_EXPORT_DIR" \
        -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
        -allowProvisioningUpdates

    wait_for_xcode_notarized_export

    local exported_app="$NOTARIZED_EXPORT_DIR/$APP_NAME.app"
    if [ ! -d "$exported_app" ]; then
        exported_app="$(find "$NOTARIZED_EXPORT_DIR" -type d -name "$APP_NAME.app" -print -quit)"
    fi

    if [ -z "$exported_app" ] || [ ! -d "$exported_app" ]; then
        fail "Notarized app not found under $NOTARIZED_EXPORT_DIR"
    fi

    echo "Copying notarized app to dist..."
    ditto "$exported_app" "$APP_DIR"

    if ! xcrun stapler validate "$APP_DIR"; then
        echo "Stapling app ticket..."
        xcrun stapler staple "$APP_DIR"
        xcrun stapler validate "$APP_DIR"
    fi

    verify_developer_id_app "$APP_DIR"
}

case "$SIGNING_MODE" in
    manual) build_manual ;;
    xcode-auto) build_xcode_auto ;;
esac

echo ""
echo "Built: $APP_DIR"
echo "Version: $VERSION ($BUILD_NUMBER)"
echo "Architectures: $ARCHS_OUT"
echo "Size: $(du -sh "$APP_DIR" | cut -f1)"
