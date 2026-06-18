#!/bin/bash
# Regenerate Resources/AppIcon.icns from tools/gen_icon.swift.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)/AppIcon.iconset"
swiftc -O -framework AppKit -o /tmp/patina_gen_icon tools/gen_icon.swift
/tmp/patina_gen_icon "$TMP"
iconutil -c icns "$TMP" -o Resources/AppIcon.icns
echo "Wrote Resources/AppIcon.icns"
