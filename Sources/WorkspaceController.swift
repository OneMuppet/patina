import AppKit

/// Ties the sidebar and editor together over a single shared NotesStore.
/// This is the window's contentViewController and the hub for all note actions.
final class WorkspaceController: NSSplitViewController, NSMenuItemValidation {

    let store = NotesStore()
    let index = LibraryIndex()
    let sidebar = SidebarViewController()
    let editor = EditorViewController()
    private lazy var palette = CommandPaletteController(index: index) { [weak self] url in
        self?.openFromLibrary(url)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        sidebar.store = store
        editor.store = store

        sidebar.onSelect = { [weak self] meta in
            self?.editor.load(meta?.url)
            Persistence.lastNote = meta?.url
            if let meta { self?.index.record(meta.url, title: meta.title, opened: true) }
        }
        editor.onTitleChange = { [weak self] in self?.updateWindowTitle() }
        editor.onRequestOpenFolder = { [weak self] in self?.openFolder(nil) }
        editor.onOpenWikiLink = { [weak self] title in self?.openWikiLink(title) }
        editor.onOpenNoteURL = { [weak self] url in self?.openFromLibrary(url) }
        editor.onSelectTag = { [weak self] tag in self?.sidebar.setSearch("#\(tag)") }
        editor.wikiTitlesProvider = { [weak self] in
            guard let self else { return [] }
            var titles = self.store.allNotes.map { $0.title }
            var seen = Set(titles)
            for e in self.index.entries where seen.insert(e.title).inserted { titles.append(e.title) }
            return titles
        }
        store.onChange = { [weak self] in
            guard let self else { return }
            self.sidebar.refresh()
            self.editor.folderChanged()
            self.editor.reconcileExternalChange()
            self.editor.refreshBacklinks()
            self.updateWindowTitle()
            self.index.registerFolder(self.store.allNotes)
        }

        let sideItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sideItem.minimumThickness = Theme.sidebarMinWidth
        sideItem.maximumThickness = Theme.sidebarMaxWidth
        sideItem.canCollapse = true
        sideItem.holdingPriority = .init(260)
        addSplitViewItem(sideItem)

        let mainItem = NSSplitViewItem(viewController: editor)
        mainItem.minimumThickness = 420
        mainItem.canCollapse = false
        addSplitViewItem(mainItem)
    }

    // MARK: Folder + note actions (reached via the responder chain / toolbar)

    func setFolder(_ url: URL, select: URL? = nil) {
        store.setFolder(url)
        if let select {
            // Load the file directly so opening *any* file works — even one that
            // isn't in the folder's note list (or is a hidden dotfile like .env).
            let csel = NotesStore.canonical(select)
            sidebar.select(csel, loadIt: false)   // highlight if it's in the list
            editor.load(csel)
            index.record(csel, title: csel.deletingPathExtension().lastPathComponent, opened: true)
            Persistence.lastNote = csel
        } else {
            editor.load(nil)
        }
        updateWindowTitle()
        Persistence.lastFolder = store.folder
    }

    @objc func openFolder(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder of notes"
        panel.begin { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.setFolder(url)
        }
    }

    @objc func newNote(_ sender: Any?) {
        guard store.folder != nil else { openFolder(nil); return }
        editor.flush()
        if let url = store.createNote() {
            sidebar.select(url, loadIt: true)
            view.window?.makeFirstResponder(editor.view)
        }
    }

    @objc func deleteNote(_ sender: Any?) {
        guard let url = editor.currentURL else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(url.deletingPathExtension().lastPathComponent)” to Trash?"
        alert.informativeText = "You can restore it from the Trash."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .warning
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let title = url.deletingPathExtension().lastPathComponent
        let trashURL = store.deleteNote(url)
        index.remove(url)
        editor.discardUnsaved()   // it's deleted on purpose — don't write a recovery sidecar
        let next = store.notes.first?.url
        editor.load(next)
        if let next { sidebar.select(next, loadIt: false) }
        if let trashURL {
            editor.showTransientBanner("Moved “\(title)” to Trash.", actionTitle: "Undo") { [weak self] in
                guard let self else { return }
                if let restored = self.store.restore(from: trashURL, to: url) {
                    self.index.record(restored, title: title, opened: true)
                    self.sidebar.select(restored, loadIt: true)
                } else {
                    NSSound.beep()
                    self.editor.showInfoBanner("Couldn't restore “\(title)” — a file with that name already exists.")
                }
            }
        }
    }

    /// Open a wiki-linked note by title — create it in the current folder if it
    /// doesn't exist yet.
    func openWikiLink(_ title: String) {
        editor.flush()
        if let meta = store.note(withTitle: title) {
            sidebar.select(meta.url, loadIt: true)
        } else if store.folder != nil, let url = store.createNamedNote(title) {
            sidebar.select(url, loadIt: true)
        } else {
            NSSound.beep()
            return
        }
        view.window?.makeFirstResponder(editor.view)
    }

    @objc func saveNote(_ sender: Any?) { editor.save(sender) }

    @objc func togglePreview(_ sender: Any?) { editor.togglePreview(sender) }

    @objc func searchNotes(_ sender: Any?) { sidebar.focusSearch() }

    @objc func showPalette(_ sender: Any?) {
        index.prune()
        palette.toggle(over: view.window)
    }

    /// Open a note chosen in the palette — switch folders first if it lives elsewhere.
    private func openFromLibrary(_ url: URL) {
        editor.flush()
        let parent = url.deletingLastPathComponent()
        if store.folder == NotesStore.canonical(parent) {
            sidebar.select(NotesStore.canonical(url), loadIt: true)
        } else {
            setFolder(parent, select: url)
        }
        view.window?.makeFirstResponder(editor.view)
    }

    /// Plain flush (app losing focus): the note stays open, so the buffer is never
    /// discarded — a conflict just leaves the banner up.
    func flushEditor() { editor.flush() }

    /// Flush when the buffer is about to be discarded for good (quit): preserves
    /// unsaved edits to a recovery sidecar if an external change blocks the save.
    func flushForDiscard() { editor.flushForDiscard() }

    // MARK: Title

    private func updateWindowTitle() {
        guard let window = view.window else { return }
        window.title = editor.currentURL != nil ? editor.currentTitle : "Patina"
        window.subtitle = store.folder?.lastPathComponent ?? ""
    }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(togglePreview(_:)):
            item.state = editor.previewVisible ? .on : .off
            return editor.canPreview
        case #selector(deleteNote(_:)):
            return editor.currentURL != nil
        case #selector(newNote(_:)):
            return true
        default:
            return true
        }
    }
}
