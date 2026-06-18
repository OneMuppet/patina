#!/bin/bash
# Build Patina.app — no Xcode project, just swiftc + a hand-assembled bundle.
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Patina"
BUILD_DIR="build"
APP="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP/Contents"
MACOS="$CONTENTS/MacOS"
RES="$CONTENTS/Resources"

rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "Compiling…"
swiftc -O -whole-module-optimization \
    -swift-version 5 \
    -framework AppKit \
    -o "$MACOS/$APP_NAME" \
    Sources/*.swift

cp Resources/Info.plist "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# App icon (generate once if missing — see tools/build_icon.sh to regenerate).
if [ -f Resources/AppIcon.icns ]; then
    cp Resources/AppIcon.icns "$RES/AppIcon.icns"
fi

# Ad-hoc codesign so Launch Services / Gatekeeper accept the local bundle.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "Built $APP"
