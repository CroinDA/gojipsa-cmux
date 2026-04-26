#!/usr/bin/env bash
# Build a Xcode-managed GOJIPSA release and optionally upload it to GitHub.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

APP_NAME="GOJIPSA"
VERSION="${VERSION:-2.0.4}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
REPO="${GITHUB_REPOSITORY:-CroinDA/gojipsa-cmux}"
TAG="v$VERSION"
DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$VERSION.dmg"
APP_DIR="$PROJECT_DIR/dist/$APP_NAME.app"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

export VERSION BUILD_NUMBER
ACTION=archive NOTARIZE=1 ./scripts/build-app.sh
./scripts/build-dmg.sh

echo "Validating notarized app..."
xcrun stapler validate "$APP_DIR"
spctl -a -vv -t exec "$APP_DIR"

echo "Checking DMG Gatekeeper assessment..."
if xcrun stapler staple "$DMG_PATH" >/dev/null 2>&1; then
    xcrun stapler validate "$DMG_PATH"
else
    echo "DMG stapling skipped; the contained app is the notarized Gatekeeper target."
fi
spctl -a -vv -t open --context context:primary-signature "$DMG_PATH" || true

[ -f "$DMG_PATH" ] || fail "Expected release DMG at $DMG_PATH"
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
