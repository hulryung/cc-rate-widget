#!/usr/bin/env bash
#
# Builds and installs a locally-signed Claude Rate Widget, without provisioning profiles.
#
# Why this exists: the App Groups entitlement makes Xcode demand a named provisioning
# profile at build time, even though nothing actually needs one — the App Group container
# and WidgetKit registration both work fine with a plain Developer ID signature. No
# xcodebuild setting turns that check off (PROVISIONING_PROFILE_REQUIRED=NO and friends
# are ignored), so we build unsigned and apply the signature ourselves afterwards.
#
# The release/notarization path is unaffected: project.yml still names the distribution
# profiles for the Release configuration, and this script never touches them.
#
# Usage:  scripts/build-local.sh [--no-install]

set -euo pipefail

CONFIG="Release"
IDENTITY="${SIGN_IDENTITY:-Developer ID Application}"
INSTALL=1
[[ "${1:-}" == "--no-install" ]] && INSTALL=0

cd "$(dirname "$0")/.."
ROOT="$PWD"
DERIVED="$ROOT/.build/xcode"
APP_NAME="Claude Rate Widget.app"

command -v xcodegen >/dev/null || { echo "xcodegen not found — brew install xcodegen"; exit 1; }

if ! security find-identity -v -p codesigning | grep -q "$IDENTITY"; then
    echo "No codesigning identity matching '$IDENTITY'." >&2
    echo "Available:" >&2
    security find-identity -v -p codesigning >&2
    exit 1
fi

echo "==> Generating project"
xcodegen generate >/dev/null

echo "==> Building ($CONFIG, unsigned)"
xcodebuild -project CCRateWidget.xcodeproj -scheme CCRateWidget -configuration "$CONFIG" \
    CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
    PROVISIONING_PROFILE_SPECIFIER="" \
    -derivedDataPath "$DERIVED" build >/dev/null

APP="$DERIVED/Build/Products/$CONFIG/$APP_NAME"
[[ -d "$APP" ]] || { echo "Build produced no app at $APP" >&2; exit 1; }

# Sign inside-out: nested code must be sealed before the outer bundle.
echo "==> Signing"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    --entitlements RateWidgetExtension/RateWidgetExtension.entitlements \
    "$APP/Contents/PlugIns/RateWidgetExtension.appex"
codesign --force --options runtime --timestamp --sign "$IDENTITY" \
    --entitlements CCRateWidget/CCRateWidget.entitlements "$APP"

codesign --verify --deep --strict "$APP"
echo "    signature valid"

if [[ $INSTALL -eq 1 ]]; then
    echo "==> Installing to /Applications"
    pkill -f "/Applications/$APP_NAME" 2>/dev/null || true
    rm -rf "/Applications/$APP_NAME"
    cp -R "$APP" /Applications/
    # Locally-built code was never quarantined, but strip the attribute defensively so a
    # copy that passed through a download or archive still launches.
    xattr -dr com.apple.quarantine "/Applications/$APP_NAME" 2>/dev/null || true
    open "/Applications/$APP_NAME"
    echo "    installed and launched"
else
    echo "==> Built at: $APP"
fi
