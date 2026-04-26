#!/usr/bin/env bash
# Build GOJIPSA.app through GOJIPSA.xcodeproj with Xcode-managed signing.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="GOJIPSA"
PROJECT_NAME="GOJIPSA"
SCHEME="${SCHEME:-GOJIPSA}"
CONFIGURATION="${CONFIGURATION:-Release}"
ACTION="${ACTION:-build}" # build | archive
NOTARIZE="${NOTARIZE:-0}"

BUILD_ROOT="${BUILD_ROOT:-$PROJECT_DIR/.build/xcode}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$BUILD_ROOT/Archives/$APP_NAME.xcarchive}"
EXPORT_OPTIONS_PLIST="${EXPORT_OPTIONS_PLIST:-$PROJECT_DIR/scripts/ExportOptions-developer-id-upload.plist}"
UPLOAD_EXPORT_DIR="$BUILD_ROOT/Exports/upload"
NOTARIZED_EXPORT_DIR="$BUILD_ROOT/Exports/notarized"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
APP_DIR="$DIST_DIR/$APP_NAME.app"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if [ ! -d "$PROJECT_NAME.xcodeproj" ]; then
    fail "$PROJECT_NAME.xcodeproj not found"
fi

if [ "$ACTION" != "build" ] && [ "$ACTION" != "archive" ]; then
    fail "ACTION must be 'build' or 'archive' (got: '$ACTION')"
fi

if [ "$NOTARIZE" != "0" ] && [ "$NOTARIZE" != "1" ]; then
    fail "NOTARIZE must be 0 or 1 (got: '$NOTARIZE')"
fi

if [ "$NOTARIZE" = "1" ] && [ "$ACTION" != "archive" ]; then
    fail "NOTARIZE=1 requires ACTION=archive"
fi

if [ -n "${VERSION:-}" ] && ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

version_settings=()
if [ -n "${VERSION:-}" ]; then
    version_settings+=(MARKETING_VERSION="$VERSION")
fi
if [ -n "${BUILD_NUMBER:-}" ]; then
    version_settings+=(CURRENT_PROJECT_VERSION="$BUILD_NUMBER")
fi

verify_app() {
    local app_dir="$1"
    local binary="$app_dir/Contents/MacOS/$APP_NAME"

    [ -d "$app_dir" ] || fail "App bundle not found: $app_dir"
    [ -x "$binary" ] || fail "App binary not executable: $binary"

    codesign --verify --deep --strict --verbose=2 "$app_dir"
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app_dir/Contents/Info.plist" | grep -q '^app\.gojipsa\.GOJIPSA$' \
        || fail "Unexpected bundle identifier in $app_dir"
}

copy_app() {
    local source_app="$1"
    rm -rf "$APP_DIR"
    mkdir -p "$DIST_DIR"
    ditto "$source_app" "$APP_DIR"
    verify_app "$APP_DIR"
}

built_products_dir() {
    xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "platform=macOS" \
        -showBuildSettings \
        ${version_settings[@]+"${version_settings[@]}"} |
        awk -F' = ' '/^[[:space:]]*BUILT_PRODUCTS_DIR = / { print $2; exit }'
}

run_xcode_build() {
    echo "Building $APP_NAME with Xcode project..."
    xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration "$CONFIGURATION" \
        -destination "platform=macOS" \
        -allowProvisioningUpdates \
        build \
        ${version_settings[@]+"${version_settings[@]}"}

    local products_dir
    products_dir="$(built_products_dir)"
    [ -n "$products_dir" ] || fail "Could not resolve BUILT_PRODUCTS_DIR"

    local built_app="$products_dir/$APP_NAME.app"
    copy_app "$built_app"
}

wait_for_notarized_export() {
    local timeout_seconds="${XCODE_NOTARY_TIMEOUT_SECONDS:-1800}"
    local poll_seconds="${XCODE_NOTARY_POLL_SECONDS:-60}"
    local deadline=$((SECONDS + timeout_seconds))
    local export_log
    export_log="$(mktemp)"

    echo "Waiting for Xcode notarization export..."
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
            fail "Timed out waiting for Xcode notarization export after ${timeout_seconds}s"
        fi

        echo "Notarization is not ready yet; retrying in ${poll_seconds}s..."
        tail -20 "$export_log" || true
        sleep "$poll_seconds"
    done
}

run_xcode_archive() {
    echo "Archiving $APP_NAME with Xcode-managed signing..."
    rm -rf "$ARCHIVE_PATH" "$UPLOAD_EXPORT_DIR" "$NOTARIZED_EXPORT_DIR"
    mkdir -p "$(dirname "$ARCHIVE_PATH")" "$UPLOAD_EXPORT_DIR"

    xcodebuild \
        -project "$PROJECT_NAME.xcodeproj" \
        -scheme "$SCHEME" \
        -configuration Release \
        -destination "generic/platform=macOS" \
        -archivePath "$ARCHIVE_PATH" \
        -allowProvisioningUpdates \
        clean archive \
        ${version_settings[@]+"${version_settings[@]}"}

    if [ "$NOTARIZE" = "1" ]; then
        [ -f "$EXPORT_OPTIONS_PLIST" ] || fail "Export options plist not found: $EXPORT_OPTIONS_PLIST"

        echo "Uploading archive through Xcode Developer ID export..."
        xcodebuild \
            -exportArchive \
            -archivePath "$ARCHIVE_PATH" \
            -exportPath "$UPLOAD_EXPORT_DIR" \
            -exportOptionsPlist "$EXPORT_OPTIONS_PLIST" \
            -allowProvisioningUpdates

        wait_for_notarized_export

        exported_app="$(find "$NOTARIZED_EXPORT_DIR" -type d -name "$APP_NAME.app" -print -quit)"
        [ -n "$exported_app" ] || fail "Notarized app not found under $NOTARIZED_EXPORT_DIR"
        copy_app "$exported_app"
        xcrun stapler validate "$APP_DIR"
    else
        copy_app "$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
    fi
}

case "$ACTION" in
    build) run_xcode_build ;;
    archive) run_xcode_archive ;;
esac

echo ""
echo "Built app: $APP_DIR"
echo "Action:    $ACTION"
echo "Config:    $CONFIGURATION"
