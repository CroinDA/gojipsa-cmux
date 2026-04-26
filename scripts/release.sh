#!/usr/bin/env bash
# release.sh - Build, notarize, and optionally upload a GOJIPSA release.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.2}"
SIGNING_MODE="${SIGNING_MODE:-manual}"
APP_NAME="GOJIPSA"
DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$VERSION.dmg"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"
TAG="v$VERSION"
REPO="${GITHUB_REPOSITORY:-CroinDA/gojipsa-cmux}"

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

if [ "$SIGNING_MODE" = "manual" ]; then
    : "${SIGN_ID:?SIGN_ID is required, e.g. Developer ID Application: NAME (TEAMID)}"
    : "${NOTARY_PROFILE:?NOTARY_PROFILE is required, e.g. AC_NOTARY}"
    export SIGN_ID NOTARY_PROFILE
fi

export VERSION SIGNING_MODE

./scripts/build-app.sh
./scripts/build-dmg.sh

if [ "$SIGNING_MODE" = "manual" ]; then
    ./scripts/notarize.sh
else
    echo ""
    echo "Validating Xcode-notarized app..."
    xcrun stapler validate "$APP_DIR"
    spctl -a -vv -t exec "$APP_DIR"

    echo ""
    echo "Checking DMG Gatekeeper assessment..."
    if xcrun stapler staple "$DMG_PATH" >/dev/null 2>&1; then
        xcrun stapler validate "$DMG_PATH"
    else
        echo "DMG stapling skipped: Xcode automatic notarization exports a stapled app, not a new DMG ticket."
        echo "The DMG remains Developer ID signed; the installed app is the notarized Gatekeeper target."
    fi
    spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" || true
fi

if [ ! -f "$DMG_PATH" ]; then
    fail "Expected release DMG at $DMG_PATH"
fi

SHA256="$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"

echo ""
echo "Release artifact ready:"
echo "  $DMG_PATH"
echo "  sha256 $SHA256"
echo ""
echo "Homebrew cask update:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""

if [ "${UPLOAD_GITHUB_RELEASE:-0}" = "1" ]; then
    command -v gh >/dev/null 2>&1 || fail "gh is required when UPLOAD_GITHUB_RELEASE=1"
    gh auth status >/dev/null

    if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
        gh release upload "$TAG" "$DMG_PATH" --repo "$REPO" --clobber
    else
        gh release create "$TAG" "$DMG_PATH" \
            --repo "$REPO" \
            --title "꼬집사 (GOJIPSA) $TAG" \
            --notes "Notarized universal macOS release."
    fi
fi
