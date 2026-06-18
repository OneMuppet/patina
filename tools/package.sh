#!/bin/bash
# Build a UNIVERSAL (Apple Silicon + Intel) Patina.app and package it as a
# drag-to-Applications .dmg and a .zip, ready to attach to a GitHub Release.
set -euo pipefail
cd "$(dirname "$0")/.."

APP_NAME="Patina"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 1.0)"
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

# Ad-hoc signature (no paid Developer ID — users clear quarantine on first open).
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

# Styled .dmg (on-brand background, big icons, drag-to-Applications arrow).
echo "Building dmg…"
DMG="$DIST/$APP_NAME-$VERSION-macos-universal.dmg"
rm -f "$DMG"

# Refresh the install-window background image.
swiftc -O -framework AppKit -o "$DIST/_dmgbg" tools/gen_dmg_bg.swift && \
    "$DIST/_dmgbg" assets/dmg-bg.png && rm -f "$DIST/_dmgbg"

if APP="$APP" python3 -m dmgbuild -s tools/dmg_settings.py "$APP_NAME" "$DMG" >/dev/null 2>&1; then
    echo "  → styled dmg via dmgbuild"
else
    echo "  → dmgbuild unavailable; building a plain dmg (run: pip3 install --user dmgbuild)"
    STAGE="$(mktemp -d)/Patina"
    mkdir -p "$STAGE"; cp -R "$APP" "$STAGE/"; ln -s /Applications "$STAGE/Applications"
    hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
    rm -rf "$STAGE"
fi

# .zip of the app
ZIP="$DIST/$APP_NAME-$VERSION-macos-universal.zip"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Done:"
echo "  $DMG  ($(du -h "$DMG" | cut -f1))"
echo "  $ZIP  ($(du -h "$ZIP" | cut -f1))"
