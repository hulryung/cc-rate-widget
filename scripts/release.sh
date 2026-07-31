#!/usr/bin/env bash
#
# Build, sign, notarize and (optionally) publish a release.
#
# The order below is the point of this script. Notarizing only the DMG leaves the app
# inside it without a stapled ticket, so once someone drags it to /Applications and is
# offline, Gatekeeper has no local proof and falls back to a network check it cannot make.
# The app has to be notarized and stapled *first*, and only then packed into a DMG that is
# itself notarized and stapled. Getting this wrong is invisible until a user without a
# network connection reports that the app won't open.
#
#   app: build → sign → notarize → staple
#   dmg: pack (stapled app inside) → sign → notarize → staple
#   verify: re-download-shaped check under com.apple.quarantine
#
# Usage:
#   scripts/release.sh                 # build, notarize, verify — publishes nothing
#   scripts/release.sh --install       # ...then install it to /Applications and run it
#   scripts/release.sh --publish       # ...then tag and publish the GitHub release
#   scripts/release.sh --check         # preflight only
#
# --install is for this machine only. It cannot help anyone else: com.apple.quarantine is
# written by whatever downloads the app — a browser, Homebrew — on their Mac, so nothing
# done here can pre-clear it for them.
#
# Environment:
#   NOTARY_PROFILE   notarytool keychain profile   (default: cc-rate-widget)
#   SIGN_ID          codesign identity             (default: the sole Developer ID Application)

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"

NOTARY_PROFILE="${NOTARY_PROFILE:-cc-rate-widget}"
DERIVED="$ROOT/.build/dd"
DIST="$ROOT/.build/dist"
SCHEME="CCRateWidget"
PROJECT="CCRateWidget.xcodeproj"

PUBLISH=0
CHECK_ONLY=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --publish) PUBLISH=1 ;;
    --check)   CHECK_ONLY=1 ;;
    --install) INSTALL=1 ;;
    -h|--help) sed -n '2,28p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

step()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
info()  { printf '    %s\n' "$*"; }
die()   { printf '\033[31merror: %s\033[0m\n' "$*" >&2; exit 1; }

MOUNT=""
cleanup() { [ -n "$MOUNT" ] && hdiutil detach "$MOUNT" -quiet 2>/dev/null || true; }
trap cleanup EXIT

# Submit and block. Written to a log rather than piped, because `... | grep -q` under
# pipefail reports the grep's early exit as a pipeline failure and would fail a release
# that Apple actually accepted.
notarize() {
  local artifact="$1" label="$2" log="$DIST/notarize-$2.log"
  mkdir -p "$DIST"
  if ! xcrun notarytool submit "$artifact" --keychain-profile "$NOTARY_PROFILE" \
        --wait --timeout 30m >"$log" 2>&1; then
    cat "$log"
    die "notarytool failed for the $label"
  fi
  # notarytool echoes the same id at upload, receipt and result; report it once.
  info "id     $(grep -m1 -E "^ *id:" "$log" | awk '{print $2}')"
  info "status $(grep -m1 -E "^ *status:" "$log" | awk '{print $2}')"
  grep -q "status: Accepted" "$log" || {
    # Rejections carry a log URL worth surfacing rather than making someone go dig.
    local sub; sub="$(grep -m1 -E "^  id:" "$log" | awk '{print $2}')"
    [ -n "$sub" ] && xcrun notarytool log "$sub" --keychain-profile "$NOTARY_PROFILE" 2>/dev/null | head -40
    die "$label was not Accepted — see $log"
  }
}

# ---------------------------------------------------------------- preflight

step "Preflight"

command -v xcodegen >/dev/null || die "xcodegen not installed (brew install xcodegen)"
command -v gh >/dev/null       || die "gh not installed (brew install gh)"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' CCRateWidget/Info.plist)"
[ -n "$VERSION" ] || die "cannot read CFBundleShortVersionString"
TAG="v$VERSION"
DMG="$DIST/ClaudeRateWidget-$TAG.dmg"
NOTES="$DIST/RELEASE_NOTES-$TAG.md"
info "version         $VERSION"

if [ -z "${SIGN_ID:-}" ]; then
  # bash 3.2 is what macOS ships, so no mapfile here.
  IDS="$(security find-identity -v -p codesigning | grep "Developer ID Application" || true)"
  COUNT="$(printf '%s' "$IDS" | grep -c . || true)"
  [ "$COUNT" -eq 0 ] && die "no Developer ID Application certificate in the keychain"
  [ "$COUNT" -gt 1 ] && die "several Developer ID certificates; set SIGN_ID to choose one"
  SIGN_ID="$(printf '%s' "$IDS" | sed -E 's/.*"(.*)".*/\1/')"
fi
info "identity        $SIGN_ID"

xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
  || die "no notarytool credentials for profile '$NOTARY_PROFILE'. Create them with:
    xcrun notarytool store-credentials \"$NOTARY_PROFILE\" --apple-id <id> --team-id <team>"
info "notary profile  $NOTARY_PROFILE"

if [ "$PUBLISH" = 1 ]; then
  [ -n "$(git status --porcelain)" ] && die "working tree is dirty; commit before publishing"
  git rev-parse "$TAG" >/dev/null 2>&1 && die "tag $TAG already exists"
  [ -f "$NOTES" ] || die "release notes missing: $NOTES"
  gh auth status >/dev/null 2>&1 || die "gh is not authenticated (gh auth login)"
  git fetch -q origin
  [ -n "$(git log --oneline origin/main..HEAD)" ] && die "local commits are not pushed to origin/main"
  info "publish         yes — will tag $TAG and create a GitHub release"
else
  info "publish         no (pass --publish to tag and release)"
fi

[ "$CHECK_ONLY" = 1 ] && { step "Preflight only — stopping"; exit 0; }

# ---------------------------------------------------------------- build

step "Test"
# Run once, keep the log, then report from it. Piping xcodebuild straight into grep would
# hand the pipeline grep's exit status and hide a failing suite.
TEST_LOG="$DIST/test.log"
mkdir -p "$DIST"
if xcodebuild test -project "$PROJECT" -scheme "$SCHEME" -destination 'platform=macOS' \
     >"$TEST_LOG" 2>&1; then
  grep -E "Executed .* tests" "$TEST_LOG" | tail -1 | sed 's/^[[:space:]]*/    /'
else
  grep -E "error:|failed|Executed .* tests" "$TEST_LOG" | tail -20
  die "tests failed — full log at $TEST_LOG"
fi

step "Build (Release)"
xcodegen generate >/dev/null
xcodebuild -project "$PROJECT" -scheme "$SCHEME" -configuration Release \
  -derivedDataPath "$DERIVED" build >/dev/null 2>&1 || die "build failed"
APP="$DERIVED/Build/Products/Release/Claude Rate Widget.app"
[ -d "$APP" ] || die "built app not found at $APP"

step "Verify the app's signature"
codesign --verify --deep --strict "$APP" || die "app signature invalid"
# Capture, then match. `producer | grep -q` is wrong under pipefail: grep exits the moment
# it matches, the producer dies of SIGPIPE, and the pipeline reports 141 — so the check
# fails precisely when it should pass.
SIG_INFO="$(codesign -dvv "$APP" 2>&1)"
grep -q "flags=.*runtime" <<<"$SIG_INFO" || die "hardened runtime is not enabled"
grep -q "^Timestamp=" <<<"$SIG_INFO" || die "no secure timestamp — notarization will reject this"
info "signed, hardened runtime, secure timestamp"

# ---------------------------------------------------------------- notarize the app

step "Notarize the app"
# notarytool takes an archive, not a bundle. The .app is stapled afterwards; the zip is
# only a transport and is thrown away.
APP_ZIP="$DIST/app-for-notarization.zip"
rm -f "$APP_ZIP"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
notarize "$APP_ZIP" "app"
rm -f "$APP_ZIP"

step "Staple the app"
# This is the step whose absence is invisible until a user is offline.
xcrun stapler staple "$APP" >/dev/null || die "stapling the app failed"
xcrun stapler validate "$APP" >/dev/null || die "app ticket did not validate"
info "ticket attached to the app bundle"

# ---------------------------------------------------------------- dmg

step "Pack the DMG"
rm -rf "$DIST/stage" "$DMG"
mkdir -p "$DIST/stage"
cp -R "$APP" "$DIST/stage/"
ln -s /Applications "$DIST/stage/Applications"
hdiutil create -volname "Claude Rate Widget" -srcfolder "$DIST/stage" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DIST/stage"
codesign --force --sign "$SIGN_ID" --timestamp "$DMG" || die "signing the DMG failed"
info "$(basename "$DMG") — $(du -h "$DMG" | cut -f1)"

step "Notarize the DMG"
notarize "$DMG" "DMG"

step "Staple the DMG"
xcrun stapler staple "$DMG" >/dev/null || die "stapling the DMG failed"
xcrun stapler validate "$DMG" >/dev/null || die "DMG ticket did not validate"

# ---------------------------------------------------------------- verify as a user sees it

step "Verify under quarantine"
# What Gatekeeper does to a file that arrived from a browser. Checking the unquarantined
# artifact proves nothing: an un-notarized build passes that and still gets blocked on a
# real download.
PROBE="$DIST/.quarantine-probe.dmg"
cp "$DMG" "$PROBE"
xattr -w com.apple.quarantine "0081;$(printf %x "$(date +%s)");Safari;$(uuidgen)" "$PROBE"

DMG_VERDICT="$(spctl -a -vvv -t open --context context:primary-signature "$PROBE" 2>&1 || true)"
grep -q "accepted" <<<"$DMG_VERDICT" || die "Gatekeeper rejected the quarantined DMG:
$DMG_VERDICT"
info "DMG accepted"

MOUNT="$(hdiutil attach "$PROBE" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)"
[ -n "$MOUNT" ] || die "could not mount the probe DMG"
APP_VERDICT="$(spctl -a -vvv "$MOUNT/Claude Rate Widget.app" 2>&1 || true)"
grep -q "accepted" <<<"$APP_VERDICT" || die "Gatekeeper rejected the app inside the DMG:
$APP_VERDICT"
xcrun stapler validate "$MOUNT/Claude Rate Widget.app" >/dev/null \
  || die "the app inside the DMG has no stapled ticket — it will fail offline"
# stapler alone is a weak proof of stapling: run it with -v and it will happily fetch the
# ticket from Apple and still say the validation worked. These two are unambiguous — the
# ticket is a real file inside the bundle, and =notarized is the requirement Gatekeeper
# itself evaluates.
[ -f "$MOUNT/Claude Rate Widget.app/Contents/CodeResources" ] \
  || die "no notarization ticket file in the bundle — stapling did not take"
codesign --test-requirement="=notarized" --verify "$MOUNT/Claude Rate Widget.app" 2>/dev/null \
  || die "the app does not satisfy the =notarized requirement"
MOUNTED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' \
  "$MOUNT/Claude Rate Widget.app/Contents/Info.plist")"
[ "$MOUNTED_VERSION" = "$VERSION" ] || die "DMG contains $MOUNTED_VERSION, expected $VERSION"
[ -f "$MOUNT/Claude Rate Widget.app/Contents/Resources/AppIcon.icns" ] \
  || die "no app icon in the bundle — Assets.xcassets is probably not in the target"
info "app accepted, ticket valid, version $MOUNTED_VERSION, icon present"
hdiutil detach "$MOUNT" -quiet; MOUNT=""
rm -f "$PROBE"

# ---------------------------------------------------------------- install locally

if [ "$INSTALL" = 1 ]; then
  step "Install to /Applications"
  # Only reached once the checks above have passed, which is what makes the last step here
  # defensible rather than a way to silence Gatekeeper.

  # Overwriting a cask-managed app leaves Homebrew describing a version that is no longer
  # on disk. That drift already happened once here: brew reported 1.5.2 for weeks while
  # /Applications held a hand-copied 1.8.0, and the mismatch only surfaced during an
  # upgrade. Say so rather than silently causing it again.
  if brew list --cask claude-rate-widget >/dev/null 2>&1; then
    CASK_VERSION="$(brew list --cask --versions claude-rate-widget 2>/dev/null | awk '{print $2}')"
    info "warning: Homebrew manages this app and reports ${CASK_VERSION:-unknown}."
    info "         Installing over it makes that record wrong until the next brew upgrade."
    info "         For a released version prefer: brew upgrade --cask claude-rate-widget"
  fi

  pkill -f "/Applications/Claude Rate Widget.app" 2>/dev/null || true
  sleep 1
  MOUNT="$(hdiutil attach "$DMG" -nobrowse -readonly | grep -o '/Volumes/.*' | head -1)"
  [ -n "$MOUNT" ] || die "could not mount the DMG to install from"
  rm -rf "/Applications/Claude Rate Widget.app"
  cp -R "$MOUNT/Claude Rate Widget.app" /Applications/
  hdiutil detach "$MOUNT" -quiet; MOUNT=""

  # Gatekeeper's first-launch check on a quarantined app asks a notarization daemon whether
  # the build is known-good. That call can fail on its own — this machine hit
  # "Error checking with notarization daemon: 3" on a build that was correctly signed,
  # notarized and stapled, and the app was blocked with "Apple could not verify...".
  # Dropping the attribute skips that path. It is safe *here* only because this script has
  # already proven the artifact notarized offline, two lines of which do not need Apple to
  # answer. Never do this to something you have not verified yourself.
  xattr -dr com.apple.quarantine "/Applications/Claude Rate Widget.app"
  codesign --test-requirement="=notarized" --verify "/Applications/Claude Rate Widget.app" 2>/dev/null \
    || die "the installed copy no longer satisfies =notarized"
  info "installed, quarantine cleared, still notarized"

  open "/Applications/Claude Rate Widget.app"
  sleep 5
  # It is a menu-bar app with no Dock icon and no window, so "did it start" is the only
  # thing observable from here.
  pgrep -f "/Applications/Claude Rate Widget.app" >/dev/null \
    && info "running — look for the gauge in the menu bar" \
    || die "the app did not stay running after launch"
fi

# ---------------------------------------------------------------- publish

if [ "$PUBLISH" = 0 ]; then
  step "Done — nothing published"
  info "artifact: $DMG"
  [ "$INSTALL" = 1 ] && info "installed:  /Applications/Claude Rate Widget.app"
  info "re-run with --publish to tag $TAG and create the GitHub release"
  exit 0
fi

step "Tag and publish $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"
gh release create "$TAG" \
  "$DMG#Claude Rate Widget $TAG (macOS, notarized)" \
  --title "$TAG" --notes-file "$NOTES" --latest

step "Confirm what was published"
# Publishing triggers update-homebrew.yml, which rewrites the cask's sha256 from the asset.
# If those disagree, `brew install` fails for everyone, so check rather than assume.
sleep 15
PUBLISHED="$DIST/.published-probe.dmg"
gh release download "$TAG" --pattern '*.dmg' --output "$PUBLISHED" --clobber
LOCAL_SHA="$(shasum -a 256 "$DMG" | cut -d' ' -f1)"
REMOTE_SHA="$(shasum -a 256 "$PUBLISHED" | cut -d' ' -f1)"
[ "$LOCAL_SHA" = "$REMOTE_SHA" ] || die "the published asset does not match the local DMG"
rm -f "$PUBLISHED"
info "asset sha256 matches: $LOCAL_SHA"
info "released: $(gh release view "$TAG" --json url -q .url)"
info "check the Homebrew cask once update-homebrew.yml finishes:"
info "  gh run list --workflow=update-homebrew.yml -L 1"
