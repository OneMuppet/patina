#!/bin/bash
# Build a SIGNED + NOTARIZED + STAPLED Patina.dmg for direct (GitHub Releases)
# distribution. After this, the download opens with no Gatekeeper warning.
#
# One-time setup (your machine, your Apple Developer account):
#   1. Install the "Developer ID Application" cert (Xcode ▸ Settings ▸ Accounts,
#      or developer.apple.com). Find its exact name:
#        security find-identity -v -p codesigning
#   2. Store a notarytool credential profile (uses an app-specific password from
#      appleid.apple.com, or an App Store Connect API key):
#        xcrun notarytool store-credentials patina-notary \
#          --apple-id "you@example.com" --team-id "TEAMID" --password "xxxx-xxxx-xxxx-xxxx"
#
# Run:
#   SIGN_ID="Developer ID Application: Your Name (TEAMID)" ./tools/notarize.sh
#   # optional: NOTARY_PROFILE=patina-notary (default)
set -euo pipefail
cd "$(dirname "$0")/.."

: "${SIGN_ID:?Set SIGN_ID, e.g. 'Developer ID Application: SnowOak Ventures (TEAMID)'}"
NOTARY_PROFILE="${NOTARY_PROFILE:-patina-notary}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
DMG="dist/Patina-$VERSION-macos-universal.dmg"

# 1. Build the signed universal app + styled dmg (package.sh signs the app when SIGN_ID is set).
SIGN_ID="$SIGN_ID" ./tools/package.sh

# 2. Sign the dmg itself.
echo "Signing dmg…"
codesign --force --timestamp --sign "$SIGN_ID" "$DMG"

# 3. Notarize (waits for Apple's verdict).
echo "Submitting to Apple notary service…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# 4. Staple the ticket so it validates offline.
echo "Stapling…"
xcrun stapler staple "$DMG"
xcrun stapler staple "dist/Patina.app" || true   # also staple the app inside

# 5. Verify the way Gatekeeper will.
echo "--- verification ---"
spctl -a -t open --context context:primary-signature -v "$DMG" || true
codesign -dv --verbose=2 "dist/Patina.app" 2>&1 | grep -E 'Authority|TeamIdentifier|Timestamp' || true
echo ""
echo "Done. Notarized + stapled: $DMG"
echo "Upload it:  gh release upload v$VERSION \"$DMG\" --clobber"
