#!/bin/bash
# Compile + run Patina's headless logic tests. Used locally and by CI.
# Runs with a throwaway HOME so it never touches your real Application Support.
set -euo pipefail
cd "$(dirname "$0")/.."

TMP="$(mktemp -d)"
BIN="$TMP/patina-tests"

swiftc -O -swift-version 5 -framework AppKit -o "$BIN" \
    tests/main.swift \
    Sources/Theme.swift \
    Sources/Markdown.swift \
    Sources/SyntaxHighlighter.swift \
    Sources/CodeHighlighter.swift \
    Sources/FolderWatcher.swift \
    Sources/NotesStore.swift \
    Sources/LibraryIndex.swift

HOME="$TMP/home" "$BIN"
