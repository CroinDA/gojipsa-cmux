#!/usr/bin/env bash
# build-app.sh — Builds Sentinel.app bundle from release binary
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-1.0.0}"
APP_NAME="Sentinel"
BUNDLE_ID="dev.croinda.sentinel"
DIST_DIR="$PROJECT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"

# Validate inputs (defense-in-depth)
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "❌ VERSION must be semver (got: '$VERSION')" >&2
    exit 1
fi
# Sanity check: APP_DIR must be inside PROJECT_DIR/dist
case "$APP_DIR" in
    "$PROJECT_DIR/dist/"*) ;;
    *) echo "❌ Refusing to operate outside dist/" >&2; exit 1 ;;
esac

echo "🔨 Building release binary..."
swift build -c release --arch arm64

echo "📦 Creating $APP_NAME.app bundle..."
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

# Copy executable
cp ".build/release/$APP_NAME" "$APP_DIR/Contents/MacOS/$APP_NAME"
chmod +x "$APP_DIR/Contents/MacOS/$APP_NAME"

# PkgInfo
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Info.plist
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME for cmux</string>
    <key>CFBundleVersion</key>
    <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>
    <string>$VERSION</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleSignature</key>
    <string>????</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Built at CMUX × AIM Hackathon Seoul 2026</string>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSAllowsArbitraryLoads</key>
        <false/>
    </dict>
</dict>
</plist>
PLIST

echo "🔏 Code signing..."
SIGN_ID="${SIGN_ID:-CroinDA HQ Development}"
if security find-identity -v -p codesigning | grep -q "$SIGN_ID"; then
    codesign --force --deep --sign "$SIGN_ID" --options=runtime "$APP_DIR" 2>&1 | tail -3
    echo "  Signed with: $SIGN_ID"
else
    codesign --force --deep --sign - "$APP_DIR" 2>&1 | tail -3
    echo "  ⚠️  Cert '$SIGN_ID' not found — used ad-hoc sign"
    echo "  ⚠️  Ad-hoc signed builds are for LOCAL DEV only."
    echo "  ⚠️  Distribution requires a Developer ID cert + notarization."
fi

# Verify signature
codesign --verify --deep --strict --verbose=2 "$APP_DIR" 2>&1 | tail -3

echo ""
echo "✅ Built: $APP_DIR"
echo "   Size: $(du -sh "$APP_DIR" | cut -f1)"
