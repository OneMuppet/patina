import AppKit

/// The content pane: a centered-column editor with live Markdown styling, a
/// toggleable preview, wiki-link autocomplete + backlinks, a word-count footer,
/// and safe reconciliation when the open file changes on disk.
final class EditorViewController: NSViewController, NSTextViewDelegate, NSTextStorageDelegate {

    var store: NotesStore!

    private(set) var currentURL: URL?
    var currentTitle: String { currentURL?.deletingPathExtension().lastPathComponent ?? "Patina" }

    // Callbacks wired by WorkspaceController.
    var onTitleChange: (() -> Void)?
    var onRequestOpenFolder: (() -> Void)?
    var onOpenWikiLink: ((String) -> Void)?
    var onOpenNoteURL: ((URL) -> Void)?
    var onSelectTag: ((String) -> Void)?
    var wikiTitlesProvider: (() -> [String])?

    // Views
    private let splitView = NSSplitView()
    private var editorTextView: CenteringTextView!
    private var previewTextView: NSTextView!
    private var editorScroll: NSScrollView!
    private var previewScroll: NSScrollView!
    private let emptyState = NSView()
    private let banner = BannerView()
    private let backlinksBar = BacklinksBar()
    private let footer = NSTextField(labelWithString: "")
    private let footerBar = NSView()
    private var completer: WikiLinkCompleter!

    // State
    private(set) var previewVisible = false
    private var currentKind: FileKind = .plainText
    private var unsupportedMessage: String?
    private var isDirty = false
    private var isSaving = false
    private var autosave: DispatchWorkItem?
    private var renderScheduled = false
    private var loadedMtime: Date?
    private var loadedSize = -1

    /// Preview only makes sense for Markdown.
    var canPreview: Bool { currentKind.isMarkdown && currentURL != nil && unsupportedMessage == nil }

    private static let maxOpenBytes = 5_000_000

    // MARK: Setup

    override func loadView() {
        let tv = CenteringTextView()
        configureEditor(tv)
        editorTextView = tv
        editorScroll = makeScroll(documentView: tv)

        let pv = NSTextView()
        pv.isEditable = false
        pv.isSelectable = true
        pv.drawsBackground = true
        pv.backgroundColor = Theme.editorBackground
        pv.textContainerInset = NSSize(width: 28, height: Theme.editorTopInset)
        pv.isAutomaticLinkDetectionEnabled = true
        pv.linkTextAttributes = [.foregroundColor: NSColor.linkColor,
                                 .underlineStyle: NSUnderlineStyle.single.rawValue]
        previewTextView = pv
        previewScroll = makeScroll(documentView: pv)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addArrangedSubview(editorScroll)
        splitView.setContentHuggingPriority(.defaultLow, for: .vertical)

        buildFooter()
        backlinksBar.onSelect = { [weak self] url in self?.onOpenNoteURL?(url) }

        let stack = NSStackView(views: [splitView, backlinksBar, footerBar])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.distribution = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: host.topAnchor),
            stack.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            // Make the stacked views span the FULL width — without this a vertical
            // NSStackView sizes them to intrinsic width and centers them, which
            // collapses the editor to ~zero width (text invisible).
            splitView.widthAnchor.constraint(equalTo: stack.widthAnchor),
            backlinksBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
            footerBar.widthAnchor.constraint(equalTo: stack.widthAnchor),
        ])
        buildEmptyState(in: host)

        // Banner lives ABOVE the empty-state overlay so undo/conflict bars stay
        // visible even when no note is open. Pinned below the toolbar.
        banner.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.topAnchor.constraint(equalTo: host.safeAreaLayoutGuide.topAnchor),
            banner.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            banner.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])
        view = host

        completer = WikiLinkCompleter(textView: editorTextView)
        completer.titlesProvider = { [weak self] in self?.wikiTitlesProvider?() ?? [] }
        updateEmptyState()
    }

    private func configureEditor(_ tv: CenteringTextView) {
        tv.delegate = self
        tv.font = Theme.editorFont
        tv.textColor = Theme.editorText
        tv.backgroundColor = Theme.editorBackground
        tv.insertionPointColor = Theme.accent
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.isHorizontallyResizable = false
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.typingAttributes = editorAttributes()
        tv.textStorage?.delegate = self
        tv.onLinkClick = { [weak self] url in self?.handleLink(url) }
    }

    private func makeScroll(documentView: NSView) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = Theme.editorBackground
        scroll.documentView = documentView
        scroll.automaticallyAdjustsContentInsets = true
        return scroll
    }

    private func buildFooter() {
        footerBar.translatesAutoresizingMaskIntoConstraints = false
        let sep = NSBox(); sep.boxType = .separator
        sep.translatesAutoresizingMaskIntoConstraints = false
        footer.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        footer.textColor = Theme.tertiaryText
        footer.alignment = .right
        footer.translatesAutoresizingMaskIntoConstraints = false
        footerBar.addSubview(sep); footerBar.addSubview(footer)
        NSLayoutConstraint.activate([
            footerBar.heightAnchor.constraint(equalToConstant: 26),
            sep.topAnchor.constraint(equalTo: footerBar.topAnchor),
            sep.leadingAnchor.constraint(equalTo: footerBar.leadingAnchor),
            sep.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor),
            footer.trailingAnchor.constraint(equalTo: footerBar.trailingAnchor, constant: -16),
            footer.centerYAnchor.constraint(equalTo: footerBar.centerYAnchor),
        ])
    }

    private func editorAttributes() -> [NSAttributedString.Key: Any] { SyntaxHighlighter.baseAttributes() }

    // MARK: Live syntax styling

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange, changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        let para = (textStorage.string as NSString).paragraphRange(for: editedRange)
        rehighlight(textStorage, range: para)
    }

    /// Style a range according to the current file kind.
    private func rehighlight(_ storage: NSTextStorage, range: NSRange) {
        switch currentKind {
        case .markdown:
            // Fenced code blocks span multiple lines, so they need whole-document
            // context. Re-style the whole doc for normal-sized notes (cheap);
            // fall back to the edited paragraph only for very large files.
            let full = NSRange(location: 0, length: storage.length)
            SyntaxHighlighter.highlight(storage, range: full.length <= 60_000 ? full : range)
        case .json, .yaml, .env:
            CodeHighlighter.highlight(storage, range: range, kind: currentKind)
        case .plainText, .code:
            let safe = NSIntersectionRange(range, NSRange(location: 0, length: storage.length))
            if safe.length > 0 { storage.setAttributes(baseAttributes(for: currentKind), range: safe) }
        }
    }

    private func baseAttributes(for kind: FileKind) -> [NSAttributedString.Key: Any] {
        switch kind {
        case .markdown, .plainText: return SyntaxHighlighter.baseAttributes()
        default: return CodeHighlighter.base()    // monospaced for code-ish files
        }
    }

    // MARK: Empty state

    private func buildEmptyState(in host: NSView) {
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.wantsLayer = true
        emptyState.layer?.backgroundColor = Theme.editorBackground.cgColor
        host.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.topAnchor.constraint(equalTo: host.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            emptyState.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: host.trailingAnchor),
        ])

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "doc.text", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: 44, weight: .ultraLight)
        icon.contentTintColor = Theme.tertiaryText
        icon.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 15, weight: .regular)
        label.textColor = Theme.secondaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false
        label.tag = 100

        let button = NSButton(title: "Open Notes Folder…", target: self, action: #selector(openFolderTapped))
        button.bezelStyle = .rounded
        button.controlSize = .large
        button.translatesAutoresizingMaskIntoConstraints = false
        button.tag = 101

        let stack = NSStackView(views: [icon, label, button])
        stack.orientation = .vertical
        stack.spacing = 16
        stack.alignment = .centerX
        stack.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor),
        ])
    }

    @objc private func openFolderTapped() { onRequestOpenFolder?() }

    private func updateEmptyState() {
        let showOverlay = currentURL == nil || unsupportedMessage != nil
        emptyState.isHidden = !showOverlay
        footerBar.isHidden = showOverlay
        guard let label = emptyState.viewWithTag(100) as? NSTextField,
              let button = emptyState.viewWithTag(101) as? NSButton else { return }
        if let msg = unsupportedMessage {
            label.stringValue = msg
            button.isHidden = true
        } else if store?.folder == nil {
            label.stringValue = "Open a notes folder to begin."
            button.isHidden = false
        } else {
            label.stringValue = "Select a note, or press ⌘N to create one."
            button.isHidden = true
        }
    }

    // MARK: Loading / saving

    func load(_ url: URL?) {
        flushForDiscard()
        let recoveryMessage = pendingRecoveryMessage
        pendingRecoveryMessage = nil
        banner.dismiss()
        completer.dismiss()
        currentURL = url
        currentKind = FileKind.of(url)
        unsupportedMessage = nil
        isDirty = false

        var text = ""
        if let url {
            switch loadContent(url) {
            case .text(let t): text = t
            case .binary: unsupportedMessage = "Patina can't display this file — it looks like binary data."
            case .tooLarge(let bytes):
                unsupportedMessage = "This file is too large to open (\(bytes / 1_000_000) MB)."
            case .unreadable:
                unsupportedMessage = "Can't open this file — it may have been moved, or you don't have permission."
            }
        }

        // Prose wraps at a readable width; code fills the pane — both left-aligned.
        editorTextView.columnMode = (currentKind == .markdown || currentKind == .plainText) ? .leftCapped : .full
        editorTextView.string = text
        editorTextView.typingAttributes = baseAttributes(for: currentKind)
        if let storage = editorTextView.textStorage, unsupportedMessage == nil {
            rehighlight(storage, range: NSRange(location: 0, length: storage.length))
        }
        editorTextView.isEditable = (url != nil && unsupportedMessage == nil)
        editorTextView.setSelectedRange(NSRange(location: 0, length: 0))
        editorTextView.scrollRangeToVisible(NSRange(location: 0, length: 0))
        (loadedMtime, loadedSize) = url.map(stamp) ?? (nil, -1)
        if !currentKind.isMarkdown { setPreview(false) }   // preview is Markdown-only
        updateEmptyState()
        updateWordCount()
        refreshBacklinks()
        onTitleChange?()
        if previewVisible { renderPreview() }
        if let recoveryMessage { showInfoBanner(recoveryMessage) }
    }

    private enum LoadResult { case text(String), binary, tooLarge(Int), unreadable }

    /// Read a file as text, refusing binary or oversized content so "open any
    /// file" never spews garbage into the editor.
    private func loadContent(_ url: URL) -> LoadResult {
        guard FileManager.default.fileExists(atPath: url.path) else { return .unreadable }
        guard let data = try? Data(contentsOf: url) else { return .unreadable }
        if data.count > Self.maxOpenBytes { return .tooLarge(data.count) }
        if data.prefix(8192).contains(0) { return .binary }      // NUL byte ⇒ binary
        if let text = String(data: data, encoding: .utf8) { return .text(text) }
        if let text = String(data: data, encoding: .isoLatin1) { return .text(text) }
        return .binary
    }

    func folderChanged() { updateEmptyState() }

    /// Show a transient banner with one action (e.g. "Undo" after a delete).
    /// The action is responsible for any follow-up UI; the bar auto-dismisses.
    func showTransientBanner(_ message: String, actionTitle: String, action: @escaping () -> Void) {
        banner.show(message, actions: [(actionTitle, action)], autoDismiss: 7)
    }

    /// A message-only banner (no buttons), auto-dismissed.
    func showInfoBanner(_ message: String) {
        banner.show(message, actions: [], autoDismiss: 4)
    }

    private func stamp(_ url: URL) -> (Date?, Int) {
        let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return (v?.contentModificationDate, v?.fileSize ?? -1)
    }

    func textDidChange(_ notification: Notification) {
        if currentKind.isMarkdown { completer.textChanged() } else { completer.dismiss() }
        updateWordCount()
        guard currentURL != nil else { return }
        isDirty = true
        scheduleAutosave()
        scheduleRender()
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        guard completer.isActive else { return false }
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)): completer.moveSelection(1); return true
        case #selector(NSResponder.moveUp(_:)): completer.moveSelection(-1); return true
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertTab(_:)):
            return completer.commit()
        case #selector(NSResponder.cancelOperation(_:)): completer.dismiss(); return true
        default: return false
        }
    }

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url = (link as? URL) ?? (link as? String).flatMap { URL(string: $0) }
        guard let url else { return false }
        handleLink(url)
        return true
    }

    /// Route a clicked link: wiki-link → open/create, tag → filter, anything else
    /// (e.g. an http link in the preview) → the system browser.
    private func handleLink(_ url: URL) {
        guard let decoded = SyntaxHighlighter.decodeLink(url) else {
            // Only follow safe web/mail links from note text — never arbitrary
            // schemes like file:// on a single click.
            if let scheme = url.scheme?.lowercased(), ["http", "https", "mailto"].contains(scheme) {
                NSWorkspace.shared.open(url)
            }
            return
        }
        if decoded.scheme == SyntaxHighlighter.noteScheme { onOpenWikiLink?(decoded.payload) }
        else if decoded.scheme == SyntaxHighlighter.tagScheme { onSelectTag?(decoded.payload) }
    }

    private func scheduleAutosave() {
        autosave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        autosave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    enum SaveResult { case saved, clean, conflict }

    @discardableResult
    private func saveNow() -> SaveResult {
        guard isDirty, let url = currentURL else { return .clean }
        let (m, s) = stamp(url)
        if m != loadedMtime || s != loadedSize {
            // The file changed on disk while we held edits — don't clobber it.
            showConflictBanner(url)
            return .conflict
        }
        writeBuffer(to: url)
        return .saved
    }

    private func writeBuffer(to url: URL) {
        isSaving = true
        store.save(editorTextView.string, to: url)
        (loadedMtime, loadedSize) = stamp(url)
        isDirty = false
        isSaving = false
    }

    @discardableResult
    func flush() -> SaveResult {
        autosave?.cancel()
        return saveNow()
    }

    /// Flush when the buffer is about to be discarded (switching notes, quitting).
    /// If an external change blocks the save, write the in-memory text to a hidden
    /// recovery sidecar so edits are never lost silently. Sets a message to surface.
    func flushForDiscard() {
        guard flush() == .conflict, let url = currentURL else { return }
        let rec = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).patina-recovery")
        let data = editorTextView.string.data(using: .utf8) ?? Data()
        if (try? data.write(to: rec)) != nil {
            isDirty = false   // preserved in the sidecar; safe to discard the buffer now
            pendingRecoveryMessage = "“\(url.lastPathComponent)” changed on disk — your unsaved edits were kept in \(rec.lastPathComponent)"
        } else {
            // Be honest: don't claim the edits were saved if the write failed.
            pendingRecoveryMessage = "“\(url.lastPathComponent)” changed on disk and your unsaved edits couldn't be written to a recovery file."
        }
    }
    private var pendingRecoveryMessage: String?

    /// Drop unsaved edits without saving (e.g. the note was just deleted).
    func discardUnsaved() { isDirty = false; autosave?.cancel() }

    /// ⌘S — Patina already autosaves; this flushes now and confirms. On a conflict
    /// it does NOT claim success — the Keep Mine / Reload banner stays up instead.
    @objc func save(_ sender: Any?) {
        guard currentURL != nil else { return }
        switch flush() {
        case .saved, .clean: flashSaved()
        case .conflict: break
        }
    }

    private var savedFlash: DispatchWorkItem?
    private func flashSaved() {
        footer.stringValue = "Saved ✓"
        savedFlash?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.updateWordCount() }
        savedFlash = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    // MARK: External-edit reconciliation

    /// Called when the folder watcher reports a change. If the open file changed
    /// underneath us, reload it (when clean) or surface a conflict (when dirty).
    func reconcileExternalChange() {
        guard !isSaving, let url = currentURL else { return }
        let (m, s) = stamp(url)
        guard m != loadedMtime || s != loadedSize else { return }
        if isDirty { showConflictBanner(url) } else { reloadFromDisk(url) }
    }

    private func reloadFromDisk(_ url: URL) {
        let sel = editorTextView.selectedRange()
        guard case .text(let text) = loadContent(url) else {
            // The file vanished or became unreadable/binary on disk — defer to the
            // full loader so the right notice shows instead of silently blanking.
            load(url)
            return
        }
        editorTextView.string = text
        if let storage = editorTextView.textStorage {
            // Re-style with the dispatcher so code files keep their syntax colors.
            rehighlight(storage, range: NSRange(location: 0, length: storage.length))
        }
        let clamped = min(sel.location, (text as NSString).length)
        editorTextView.setSelectedRange(NSRange(location: clamped, length: 0))
        (loadedMtime, loadedSize) = stamp(url)
        isDirty = false
        banner.dismiss()
        updateWordCount()
        refreshBacklinks()
        if previewVisible { renderPreview() }
    }

    private func showConflictBanner(_ url: URL) {
        banner.show("“\(currentTitle)” was changed by another app.", actions: [
            ("Keep Mine", { [weak self] in self?.writeBuffer(to: url); self?.banner.dismiss() }),
            ("Reload", { [weak self] in self?.reloadFromDisk(url) }),
        ])
    }

    // MARK: Backlinks + word count

    func refreshBacklinks() {
        guard currentKind.isMarkdown, let url = currentURL else { backlinksBar.set([]); return }
        let items = store.backlinks(toTitle: currentTitle, excluding: url).map { (title: $0.title, url: $0.url) }
        backlinksBar.set(items)
    }

    private func updateWordCount() {
        guard currentURL != nil, unsupportedMessage == nil else { footer.stringValue = ""; return }
        let s = editorTextView.string
        let chars = s.count
        if currentKind.isMarkdown || currentKind == .plainText {
            let words = s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" }).count
            if words == 0 {
                footer.stringValue = "Empty"
            } else {
                let mins = max(1, Int((Double(words) / 200.0).rounded(.up)))
                footer.stringValue = "\(words) words · \(chars) characters · \(mins) min read"
            }
        } else {
            let lines = s.isEmpty ? 0 : s.reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
            footer.stringValue = s.isEmpty ? "Empty" : "\(lines) lines · \(chars) characters"
        }
    }

    // MARK: Markdown formatting commands (⌘B, ⌘I, …)

    @objc func toggleBold(_ sender: Any?) { wrap("**", "**") }
    @objc func toggleItalic(_ sender: Any?) { wrap("_", "_") }
    @objc func toggleInlineCode(_ sender: Any?) { wrap("`", "`") }

    @objc func insertLink(_ sender: Any?) {
        guard editorTextView.isEditable else { return }
        let tv = editorTextView!
        let r = tv.selectedRange()
        let sel = (tv.string as NSString).substring(with: r)
        tv.insertText("[\(sel)](url)", replacementRange: r)
        let urlLoc = r.location + 1 + (sel as NSString).length + 2
        tv.setSelectedRange(NSRange(location: urlLoc, length: 3))
    }

    @objc func toggleHeading(_ sender: Any?) { prefixLine(toggling: "# ") }
    @objc func toggleBulletList(_ sender: Any?) { prefixLine(toggling: "- ") }

    private func wrap(_ left: String, _ right: String) {
        guard editorTextView.isEditable else { return }
        let tv = editorTextView!
        let r = tv.selectedRange()
        let sel = (tv.string as NSString).substring(with: r)
        let lLen = (left as NSString).length
        if sel.hasPrefix(left), sel.hasSuffix(right), sel.count >= left.count + right.count {
            let inner = String(sel.dropFirst(left.count).dropLast(right.count))
            tv.insertText(inner, replacementRange: r)
            tv.setSelectedRange(NSRange(location: r.location, length: (inner as NSString).length))
            return
        }
        tv.insertText(left + sel + right, replacementRange: r)
        tv.setSelectedRange(NSRange(location: r.location + lLen, length: (sel as NSString).length))
    }

    private func prefixLine(toggling prefix: String) {
        guard editorTextView.isEditable else { return }
        let tv = editorTextView!
        let ns = tv.string as NSString
        let lineRange = ns.lineRange(for: NSRange(location: tv.selectedRange().location, length: 0))
        let line = ns.substring(with: lineRange)
        if line.hasPrefix(prefix) {
            tv.insertText(String(line.dropFirst(prefix.count)), replacementRange: lineRange)
        } else {
            tv.insertText(prefix + line, replacementRange: lineRange)
        }
    }

    // MARK: Preview

    @objc func togglePreview(_ sender: Any?) {
        if !previewVisible && !canPreview { NSSound.beep(); return }
        setPreview(!previewVisible)
    }

    private func setPreview(_ on: Bool) {
        guard previewVisible != on else { return }
        previewVisible = on
        if on {
            splitView.addArrangedSubview(previewScroll)
            splitView.setPosition(splitView.bounds.width / 2, ofDividerAt: 0)
            renderPreview()
        } else {
            previewScroll.removeFromSuperview()
        }
    }

    private func scheduleRender() {
        guard previewVisible, !renderScheduled else { return }
        renderScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.renderScheduled = false
            self?.renderPreview()
        }
    }

    private func renderPreview() {
        guard previewVisible else { return }
        previewTextView.textStorage?.setAttributedString(Markdown.render(editorTextView.string))
    }
}
