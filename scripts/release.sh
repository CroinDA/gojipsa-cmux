#!/usr/bin/env bash
# release.sh - Build, notarize, and optionally upload a GOJIPSA release.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.1}"
APP_NAME="GOJIPSA"
DMG_PATH="$PROJECT_DIR/dist/$APP_NAME-$VERSION.dmg"
TAG="v$VERSION"
REPO="${GITHUB_REPOSITORY:-CroinDA/gojipsa-cmux}"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    fail "VERSION must be semver (got: '$VERSION')"
fi

: "${SIGN_ID:?SIGN_ID is required, e.g. Developer ID Application: NAME (TEAMID)}"
: "${NOTARY_PROFILE:?NOTARY_PROFILE is required, e.g. AC_NOTARY}"

export VERSION SIGN_ID NOTARY_PROFILE

./scripts/build-app.sh
./scripts/build-dmg.sh
./scripts/notarize.sh

if [ ! -f "$DMG_PATH" ]; then
    fail "Expected notarized DMG at $DMG_PATH"
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
