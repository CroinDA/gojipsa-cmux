#!/usr/bin/env bash
# notarize.sh — Submit DMG to Apple notary service, wait, staple, verify.
# Requires: NOTARY_PROFILE env-var (created via `xcrun notarytool store-credentials`)
set -eo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"

VERSION="${VERSION:-2.0.2}"
APP_NAME="GOJIPSA"
DIST_DIR="$PROJECT_DIR/dist"
DMG_PATH="$DIST_DIR/$APP_NAME-$VERSION.dmg"
APP_DIR="$DIST_DIR/$APP_NAME.app"

# ─── Validate inputs ───
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[A-Za-z0-9.-]+)?$ ]]; then
    echo "❌ VERSION must be semver (got: '$VERSION')" >&2
    exit 1
fi

if [ -z "${NOTARY_PROFILE:-}" ]; then
    echo "❌ NOTARY_PROFILE env-var not set." >&2
    echo "   First run: xcrun notarytool store-credentials \"AC_NOTARY\" \\" >&2
    echo "                --apple-id YOUR_APPLE_ID --team-id TEAM_ID --password APP_PWD" >&2
    echo "   Then:       NOTARY_PROFILE=AC_NOTARY ./scripts/notarize.sh" >&2
    exit 1
fi
# Restrict profile name format (defense-in-depth)
if ! [[ "$NOTARY_PROFILE" =~ ^[A-Za-z0-9._-]{1,64}$ ]]; then
    echo "❌ NOTARY_PROFILE has invalid characters" >&2
    exit 1
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "❌ DMG not found at $DMG_PATH" >&2
    echo "   Run: ./scripts/build-app.sh && ./scripts/build-dmg.sh" >&2
    exit 1
fi

if [ ! -d "$APP_DIR" ]; then
    echo "❌ App not found at $APP_DIR" >&2
    echo "   Run: ./scripts/build-app.sh && ./scripts/build-dmg.sh" >&2
    exit 1
fi

# ─── Pre-check: app must be Hardened Runtime + Developer ID signed ───
echo "🔍 Pre-flight checks..."
auth=$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | grep "Authority=Developer ID Application" || true)
if [ -z "$auth" ]; then
    echo "❌ $APP_DIR is not signed with Developer ID Application." >&2
    echo "   Re-run with proper SIGN_ID:" >&2
    echo "     SIGN_ID=\"Developer ID Application: NAME (TEAMID)\" ./scripts/build-app.sh" >&2
    exit 1
fi
runtime=$(codesign -dv --verbose=4 "$APP_DIR" 2>&1 | grep "flags=.*runtime" || true)
if [ -z "$runtime" ]; then
    echo "❌ $APP_DIR missing Hardened Runtime." >&2
    echo "   build-app.sh should add ENABLE_HARDENED_RUNTIME=YES — please rebuild." >&2
    exit 1
fi
echo "  ✅ Developer ID signed + Hardened Runtime"

# Pre-check: DMG itself must be Developer ID signed
dmg_auth=$(codesign -dv --verbose=4 "$DMG_PATH" 2>&1 | grep "Authority=Developer ID Application" || true)
if [ -z "$dmg_auth" ]; then
    echo "❌ $DMG_PATH is not Developer ID signed. Re-run build-dmg.sh with proper SIGN_ID." >&2
    exit 1
fi
echo "  ✅ DMG signed with Developer ID"

# ─── Submit to Apple notary service ───
echo ""
echo "📤 Submitting $DMG_PATH to Apple notary service..."
echo "   (This typically takes 2-15 minutes; --wait blocks until done)"

# Capture submission output
SUBMIT_LOG=$(mktemp)
trap 'rm -f "$SUBMIT_LOG"' EXIT

if xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait 2>&1 | tee "$SUBMIT_LOG"; then
    :
else
    echo "" >&2
    echo "❌ notarytool submit failed." >&2
    exit 1
fi

# Primary success signal: notarytool --wait exits 0 ONLY when status is "Accepted".
# We still parse the output for diagnostic info on failure, but don't gate on it.
SUBMISSION_ID=$(grep -E "^\s*id:" "$SUBMIT_LOG" | head -1 | awk '{print $2}' | head -c 64)
STATUS=$(grep -E "^\s*status:" "$SUBMIT_LOG" | tail -1 | awk '{print $2}' | head -c 32)

# Sanitize SUBMISSION_ID before using in another command (defense vs CLI output drift)
if ! [[ "$SUBMISSION_ID" =~ ^[A-Za-z0-9-]{8,64}$ ]]; then
    SUBMISSION_ID=""
fi

echo ""
echo "   Submission ID: ${SUBMISSION_ID:-<unparsed>}"
echo "   Status:        ${STATUS:-<unparsed>}"

if [ -n "$STATUS" ] && [ "$STATUS" != "Accepted" ]; then
    echo "" >&2
    echo "❌ Notarization not accepted." >&2
    if [ -n "$SUBMISSION_ID" ]; then
        echo "   Fetching detailed log..." >&2
        xcrun notarytool log "$SUBMISSION_ID" --keychain-profile "$NOTARY_PROFILE" || true
    fi
    exit 1
fi

# ─── Staple the ticket onto the DMG ───
echo ""
echo "📎 Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

# Also staple the .app inside (best practice for offline verification)
if [ -d "$APP_DIR" ]; then
    xcrun stapler staple "$APP_DIR" 2>&1 | tail -3 || echo "  (app staple skipped — DMG staple is sufficient)"
fi

# ─── Verify with spctl (Gatekeeper assessment) ───
echo ""
echo "🔎 Verifying with Gatekeeper..."
spctl -a -t open --context context:primary-signature -vv "$DMG_PATH" 2>&1 | tail -3

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Notarized & stapled: $DMG_PATH"
echo "   SHA256: $(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)"
echo "   Ready for distribution."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
