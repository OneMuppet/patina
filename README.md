<p align="center">
  <img src="assets/banner.svg" alt="Patina — a fast, plain-text editor for any file" width="100%">
</p>

# Patina

A hyper-efficient macOS app for any text-ish file. Markdown gets a beautiful
rendered view; code (`json` / `yaml` / `.env`) gets syntax highlighting;
everything else just opens, instantly. Native AppKit, no Xcode project, no web
view, zero third-party dependencies — links only system frameworks.

Make it the default for `.md`, `.txt`, `.env`, `.json`, `.yaml`, and even unknown
file types, and it opens them in a blink. Binary or oversized files are detected
and shown a friendly notice instead of a screenful of garbage.

Your files stay plain files. Patina never locks them in a database — it's a fast,
beautiful lens over a directory you already own.

## Download

[![Download Patina for macOS](https://img.shields.io/badge/Download-Patina%20for%20macOS-C7752E?style=for-the-badge)](../../releases/latest)

Grab the latest **`.dmg`** from the [**Releases**](../../releases/latest) page,
open it, and drag **Patina** into **Applications**. It's a **universal** build —
runs natively on Apple Silicon and Intel.

> **First launch (important):** Patina is a free, unsigned build — it isn't
> notarized through a paid Apple Developer account, so the first time you open it
> macOS Gatekeeper blocks it with *"Apple could not verify Patina is free of
> malware."* This is expected; **don't click Move to Bin.** Clear the quarantine
> flag once, from Terminal:
> ```sh
> xattr -dr com.apple.quarantine /Applications/Patina.app
> ```
> then double-click Patina. **No Terminal?** Try to open it once, then go to
> **System Settings → Privacy & Security**, scroll to *"Patina was blocked…"* and
> click **Open Anyway**. (On macOS Sequoia/Tahoe the old right-click → Open trick
> no longer works.)

Prefer to compile it yourself? See [**Build**](#build) below.

## Features

- **Opens anything text** — Markdown renders beautifully; `.json`, `.yaml`/`.yml`,
  and `.env` get live syntax highlighting (keys, strings, numbers, comments);
  `.txt` and unknown files open as fast plain text. Binary/oversized files are
  detected and declined gracefully.
- **`[[wiki-links]]` + backlinks** — type `[[` for fuzzy autocomplete over your
  whole library; `[[Note]]` becomes a clickable link (and is *created* on click
  if it doesn't exist yet). Each note shows a "Linked from" strip of the notes
  that point at it. The links are literal `[[…]]` text — open the file anywhere
  and it's still readable. No database, no link table.
- **`#tags`** — `#tag` is styled inline and clickable; clicking filters the
  sidebar to it. Typing `#tag` in search already filters by full text. Tags are
  just words in the file — nothing to set up, nothing to migrate.
- **Never lose an edit** — if the open file changes on disk (another app, git,
  sync), Patina reloads it when you have no unsaved edits, or shows a
  *Keep Mine / Reload* banner when you do — it never silently overwrites.
- **Undo delete** — deleting moves to Trash and offers a one-click Undo.
- **Word count + reading time** — a live footer with words · characters · minutes.
- **Command Palette (⌘K)** — fuzzy quick-open across **every note you've ever
  opened**, in any folder. Patina keeps a self-healing index (JSON in Application
  Support) that remembers your files and prunes ones that no longer exist.
- **Live Markdown styling** — headings, **bold**, *italic*, `code`, links, and
  list/quote markers are styled right in the editor as you type; the syntax
  markers dim so the prose stands out.
- **Classic shortcuts** — ⌘B bold, ⌘I italic, ⌘⌥C inline code, ⌘⇧K link,
  ⌘⌥H heading, ⌘⇧L bullet list — each toggles the selection.
- **Folder library + live search** — point Patina at a folder; the vibrant
  sidebar lists every note (title · snippet · date), newest first. Search filters
  by **filename and full text** as you type.
- **Live folder watching** — add, rename, or delete files in Finder and the
  sidebar updates itself (FSEvents).
- **Autosave to disk** — edits are written back to the file ~0.6 s after you stop
  typing, and flushed on note-switch, app-hide, and quit. No save dialogs.
- **Beautiful editing** — a centered, fixed-width reading column with generous
  line spacing; the measure stays comfortable at any window size.
- **Native Markdown preview** — ⌘⇧P renders to a native `NSAttributedString`
  (no WebView), so the preview is effectively free.
- **Inline rename** — double-click a note's title in the sidebar to rename the
  file on disk.
- **Reopens where you left off** — last folder, note, and window frame restored.
- **Set it as your default** — registers UTIs for `.txt`/`.md`; double-click a
  file in Finder and Patina opens its folder with that note selected.

## Build

```sh
./build.sh        # → build/Patina.app  (swiftc, no Xcode project)
```

Requires the Swift toolchain (ships with Xcode / Command Line Tools).

## Install + make it the default app

```sh
./install.sh      # copies to /Applications and registers with Launch Services
```

With [`duti`](https://github.com/moretension/duti) installed (`brew install duti`)
the script also makes Patina the default opener for `.txt` and `.md`. Otherwise:
right-click a file → *Get Info* → *Open with* → Patina → *Change All…*

## Keys

| Action | Shortcut |
|---|---|
| Quick Open (command palette) | ⌘K |
| New note | ⌘N |
| Open notes folder | ⌘⇧O |
| Move note to Trash | ⌘⌫ |
| Search notes | ⌘⌥F |
| Find in note | ⌘F |
| Toggle sidebar | ⌃⌘S |
| Toggle Markdown preview | ⌘⇧P |
| Bold / Italic | ⌘B / ⌘I |
| Inline code / Link | ⌘⌥C / ⌘⇧K |
| Heading / Bullet list | ⌘⌥H / ⌘⇧L |
| Rename note | double-click its title |

## Markdown supported in preview

Headings, **bold**, *italic*, `inline code`, fenced code blocks, links,
unordered/ordered lists, blockquotes, horizontal rules.

## Architecture

```
Sources/
  main.swift                  # entry point
  Theme.swift                 # all visual tuning + centered-column text view
  AppDelegate.swift           # window chrome, toolbar, menu, persistence, open-from-Finder
  WorkspaceController.swift    # split-view hub; wires sidebar ↔ editor ↔ palette over one store
  SidebarViewController.swift  # search + source-list note rows + inline rename
  EditorViewController.swift   # centered editor, autosave, live preview, formatting cmds
  SyntaxHighlighter.swift      # live in-editor Markdown styling + wiki-link/tag links
  CodeHighlighter.swift        # FileKind detection + json/yaml/.env syntax highlighting
  CommandPalette.swift         # ⌘K fuzzy quick-open panel
  WikiLinkCompleter.swift      # [[ autocomplete panel
  EditorAccessories.swift      # conflict/undo banner, backlinks bar
  NotesStore.swift            # folder scan, search, backlinks, mutations
  LibraryIndex.swift          # persistent index of all opened notes (+ auto-prune)
  FolderWatcher.swift         # FSEvents wrapper for live updates
  Markdown.swift              # dependency-free Markdown → NSAttributedString
  Persistence.swift           # last folder / note / frame
Resources/Info.plist          # bundle id + document-type / UTI declarations
Resources/AppIcon.icns        # generated by tools/build_icon.sh
build.sh / install.sh
```

Notes stay plain files; Patina is a thin, fast, native layer over a folder.

## License

[MIT](LICENSE) © 2026 David Borgenvik
