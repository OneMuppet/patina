#!/bin/bash
# Build a UNIVERSAL (Apple Silicon + Intel) Patina.app and package it as a
# drag-to-Applications .dmg and a .zip, ready to attach to a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Patina"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
# Distinct VOLUME name so Finder can't reuse a cached window layout from an
# earlier disk image (macOS caches DMG window state by volume name).
VOLNAME="Install Patina"
DEPLOY="13.0"
DIST="dist"
APP="$DIST/$APP_NAME.app"
CONTENTS="$APP/Contents"

rm -rf "$DIST"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

echo "Compiling universal binary (arm64 + x86_64)…"
swiftc -O -whole-module-optimization -swift-version 5 -framework AppKit \
    -target arm64-apple-macosx$DEPLOY  -o "$DIST/patina-arm64"  Sources/*.swift
swiftc -O -whole-module-optimization -swift-version 5 -framework AppKit \
    -target x86_64-apple-macosx$DEPLOY -o "$DIST/patina-x86_64" Sources/*.swift
lipo -create -output "$CONTENTS/MacOS/$APP_NAME" "$DIST/patina-arm64" "$DIST/patina-x86_64"
rm -f "$DIST/patina-arm64" "$DIST/patina-x86_64"
echo "  → $(lipo -archs "$CONTENTS/MacOS/$APP_NAME")"

cp Resources/Info.plist "$CONTENTS/Info.plist"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# Sign the app. With a Developer ID in $SIGN_ID we use a hardened runtime +
# secure timestamp (required for notarization); otherwise an ad-hoc signature
# (users clear quarantine on first open).
if [ -n "${SIGN_ID:-}" ]; then
    echo "Signing with: $SIGN_ID"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$CONTENTS/MacOS/$APP_NAME"
    codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
fi

# Styled .dmg (on-brand background, big icons, drag-to-Applications arrow).
echo "Building dmg…"
DMG="$DIST/$APP_NAME-$VERSION-macos-universal.dmg"
rm -f "$DMG"

# Refresh the install-window background image.
swiftc -O -framework AppKit -o "$DIST/_dmgbg" tools/gen_dmg_bg.swift && \
    "$DIST/_dmgbg" assets/dmg-bg.png && rm -f "$DIST/_dmgbg"

if APP="$APP" VOL="$VOLNAME" OUT="$DMG" BG="assets/dmg-bg.png" ICNS="Resources/AppIcon.icns" \
        python3 tools/make_dmg.py >/dev/null 2>&1; then
    echo "  → styled dmg (bookmark background, Retina, hidden files parked)"
else
    echo "  → styled build failed; plain dmg (needs: pip3 install --user ds_store mac_alias)"
    STAGE="$(mktemp -d)/Patina"
    mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
fi

# .zip of the app
ZIP="$DIST/$APP_NAME-$VERSION-macos-universal.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Done:"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
echo "  $ZIP  ($(du -h "$ZIP" | cut -f1))"
