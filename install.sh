#!/bin/bash
# Install Patina into /Applications, register it with Launch Services, and
# (optionally) make it the default app for .txt and .md.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Patina.app"
DEST="/Applications/Patina.app"

if [ ! -d "$APP" ]; then
    echo "Build first:  ./build.sh"
    exit 1
fi

echo "Installing to $DEST …"
rm -rf "$DEST"
cp -R "$APP" "$DEST"

# Register the bundle so Launch Services learns its document types.
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
"$LSREGISTER" -f "$DEST"
echo "Registered."

# Set as default handler if `duti` is available (brew install duti).
if command -v duti >/dev/null 2>&1; then
    duti -s com.davidborgenvik.patina public.plain-text all
    duti -s com.davidborgenvik.patina public.text all
    duti -s com.davidborgenvik.patina net.daringfireball.markdown all
    duti -s com.davidborgenvik.patina public.json all
    duti -s com.davidborgenvik.patina public.yaml all
    for ext in txt md markdown json yaml yml env toml ini conf cfg log csv xml; do
        duti -s com.davidborgenvik.patina ".$ext" all
    done
    # Become the fallback editor for files with no/unknown type, too.
    duti -s com.davidborgenvik.patina public.data all 2>/dev/null || true
    echo "Set Patina as the default for text, markdown, json, yaml, .env and unknown files (via duti)."
else
    echo
    echo "To make Patina the default app:"
    echo "  • Right-click a file → Get Info → 'Open with' → Patina → 'Change All…'"
    echo "  • Or:  brew install duti  and re-run this script to set txt/md/json/yaml/.env + unknown files."
fi
