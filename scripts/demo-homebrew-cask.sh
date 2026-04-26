#!/usr/bin/env bash
# Build and verify a local Homebrew cask demo for the current GOJIPSA release.
set -euo pipefail

VERSION="${VERSION:-2.0.2}"
SHA256="${SHA256:-588739e8f8ae190674ddba03fc24070b951003d7b6e918b8cba67f4399a85508}"
REPO="${REPO:-CroinDA/gojipsa-cmux}"
CASK_TOKEN="${CASK_TOKEN:-gojipsa}"
APP_BUNDLE="${APP_BUNDLE:-GOJIPSA.app}"
RUN_INSTALL="${RUN_INSTALL:-1}"
RUN_OPEN="${RUN_OPEN:-0}"
KEEP_WORKDIR="${KEEP_WORKDIR:-0}"
USE_LOCAL_DMG="${USE_LOCAL_DMG:-0}"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DEMO_TAP="${DEMO_TAP:-gojipsa/cask-demo-$(date +%s)-$$}"
FULL_CASK_TOKEN="$DEMO_TAP/$CASK_TOKEN"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "ERROR: VERSION must be semver (got: '$VERSION')" >&2
    exit 1
fi

if ! [[ "$SHA256" =~ ^[0-9a-f]{64}$ ]]; then
    echo "ERROR: SHA256 must be a lowercase 64-character SHA-256 digest." >&2
    exit 1
fi

command -v brew >/dev/null 2>&1 || {
    echo "ERROR: Homebrew is required." >&2
    exit 1
}

WORKDIR="${WORKDIR:-$(mktemp -d "${TMPDIR:-/tmp}/gojipsa-cask-demo.XXXXXX")}"
APPDIR="$WORKDIR/Applications"
CACHE_DIR="$WORKDIR/HomebrewCache"
INSTALLED_APP="$APPDIR/$APP_BUNDLE"
INSTALLED_BY_SCRIPT=0
TAP_CREATED=0
TAP_DIR=""
CASK_FILE=""

cleanup() {
    if [ "$INSTALLED_BY_SCRIPT" = "1" ]; then
        brew uninstall --cask --force "$FULL_CASK_TOKEN" >/dev/null 2>&1 || true
    fi
    if [ "$TAP_CREATED" = "1" ]; then
        brew untap --force "$DEMO_TAP" >/dev/null 2>&1 || true
    fi
    if [ "$KEEP_WORKDIR" != "1" ]; then
        rm -rf "$WORKDIR"
    else
        echo "Kept demo workdir: $WORKDIR"
    fi
}
trap cleanup EXIT

mkdir -p "$APPDIR" "$CACHE_DIR"

export HOMEBREW_NO_AUTO_UPDATE="${HOMEBREW_NO_AUTO_UPDATE:-1}"
export HOMEBREW_NO_INSTALL_CLEANUP="${HOMEBREW_NO_INSTALL_CLEANUP:-1}"
export HOMEBREW_NO_ENV_HINTS="${HOMEBREW_NO_ENV_HINTS:-1}"
export HOMEBREW_CACHE="${HOMEBREW_CACHE:-$CACHE_DIR}"

if [ "$USE_LOCAL_DMG" = "1" ]; then
    LOCAL_DMG="${LOCAL_DMG:-$PROJECT_DIR/dist/GOJIPSA-$VERSION.dmg}"
    if [ ! -f "$LOCAL_DMG" ]; then
        echo "ERROR: LOCAL_DMG does not exist: $LOCAL_DMG" >&2
        exit 1
    fi
    URL="file://$LOCAL_DMG"
else
    URL="https://github.com/$REPO/releases/download/v#{version}/GOJIPSA-#{version}.dmg"
fi

echo "Creating temporary Homebrew tap:"
echo "  $DEMO_TAP"
brew tap-new "$DEMO_TAP" --no-git >/dev/null
TAP_CREATED=1
TAP_DIR="$(brew --repository "$DEMO_TAP")"
CASK_DIR="$TAP_DIR/Casks"
CASK_FILE="$CASK_DIR/$CASK_TOKEN.rb"
mkdir -p "$CASK_DIR"

{
    cat <<CASK
cask "$CASK_TOKEN" do
  version "$VERSION"
  sha256 "$SHA256"

CASK
    if [ "$USE_LOCAL_DMG" = "1" ]; then
        echo "  url \"$URL\""
    else
        echo "  url \"$URL\""
    fi
    cat <<CASK
  name "GOJIPSA"
  desc "Context-aware native guardian for cmux"
  homepage "https://github.com/$REPO"

  depends_on macos: ">= :ventura"

  app "$APP_BUNDLE"

  caveats do
    <<~EOS
      cmux is required separately. Install and configure cmux before using GOJIPSA.
    EOS
  end
end
CASK
} >"$CASK_FILE"

echo "Generated local cask:"
echo "  $CASK_FILE"
echo "  token: $FULL_CASK_TOKEN"
echo ""
grep -E '^(  version|  sha256|  url)' "$CASK_FILE"
echo ""

echo "Running brew style..."
brew style --cask "$FULL_CASK_TOKEN"

echo "Running brew audit..."
brew audit --cask "$FULL_CASK_TOKEN"

echo "Running brew fetch..."
brew fetch --cask --force --retry "$FULL_CASK_TOKEN"

if [ "$RUN_INSTALL" != "1" ]; then
    echo ""
    echo "RUN_INSTALL=0, skipping install/Gatekeeper verification."
    echo "To run the full local demo:"
    echo "  ./scripts/demo-homebrew-cask.sh"
    exit 0
fi

if brew list --cask "$CASK_TOKEN" >/dev/null 2>&1; then
    echo "ERROR: Homebrew cask '$CASK_TOKEN' is already installed." >&2
    echo "Uninstall it first, or run RUN_INSTALL=0 ./scripts/demo-homebrew-cask.sh for fetch-only verification." >&2
    exit 1
fi

echo "Installing into temporary appdir:"
echo "  $APPDIR"
brew install --cask --appdir="$APPDIR" "$FULL_CASK_TOKEN"
INSTALLED_BY_SCRIPT=1

if [ ! -d "$INSTALLED_APP" ]; then
    echo "ERROR: expected installed app at $INSTALLED_APP" >&2
    exit 1
fi

echo "Verifying installed app signature..."
codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP"

echo "Validating stapled notarization ticket..."
xcrun stapler validate "$INSTALLED_APP"

echo "Running Gatekeeper assessment..."
spctl -a -vv -t exec "$INSTALLED_APP"

if [ "$RUN_OPEN" = "1" ]; then
    echo "Opening installed app..."
    open "$INSTALLED_APP"
fi

echo ""
echo "Homebrew cask demo succeeded."
echo "Tap repo update values:"
echo "  version \"$VERSION\""
echo "  sha256 \"$SHA256\""
