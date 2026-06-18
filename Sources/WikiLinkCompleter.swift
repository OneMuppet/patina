import AppKit

/// Inline autocomplete for `[[wiki-links]]`. When the caret sits inside an open
/// `[[…` token, a small panel offers matching note titles; Enter inserts
/// `Title]]`. Keyboard nav is driven by the editor's doCommandBy (the editor
/// keeps focus — this panel never becomes key).
final class WikiLinkCompleter: NSObject, NSTableViewDataSource, NSTableViewDelegate {

    private weak var textView: NSTextView?
    var titlesProvider: () -> [String] = { [] }

    private let panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
                                     styleMask: [.borderless, .nonactivatingPanel],
                                     backing: .buffered, defer: true)
    private let tableView = NSTableView()
    private var matches: [String] = []
    private var triggerStart = -1          // location just after the "[["
    private let rowH: CGFloat = 26
    private let maxRows = 6

    var isActive: Bool { panel.isVisible }

    init(textView: NSTextView) {
        self.textView = textView
        super.init()
        build()
    }

    private func build() {
        let vfx = NSVisualEffectView()
        vfx.material = .menu
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 8
        vfx.layer?.masksToBounds = true

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowHeight = rowH
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.addTableColumn(NSTableColumn(identifier: .init("c")))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.borderType = .noBorder
        vfx.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: vfx.topAnchor, constant: 4),
            scroll.bottomAnchor.constraint(equalTo: vfx.bottomAnchor, constant: -4),
            scroll.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 4),
            scroll.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -4),
        ])

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.contentView = vfx
    }

    // MARK: Trigger detection

    func textChanged() {
        guard let tv = textView else { return }
        let sel = tv.selectedRange()
        guard sel.length == 0 else { dismiss(); return }
        let caret = sel.location
        let ns = tv.string as NSString
        let lineStart = ns.lineRange(for: NSRange(location: caret, length: 0)).location
        let prefix = ns.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        guard let openRange = prefix.range(of: "[[", options: .backwards) else { dismiss(); return }
        let afterOpen = String(prefix[openRange.upperBound...])
        if afterOpen.contains("]") || afterOpen.contains("[") { dismiss(); return }
        triggerStart = caret - (afterOpen as NSString).length
        showMatches(query: afterOpen)
    }

    private func showMatches(query: String) {
        let q = query.lowercased()
        var seen = Set<String>()
        let all = titlesProvider().filter { seen.insert($0).inserted }
        matches = Array((q.isEmpty ? all : all.filter { LibraryIndex.fuzzy(q, in: $0.lowercased()) }).prefix(40))
        if matches.isEmpty { dismiss(); return }
        tableView.reloadData()
        tableView.selectRowIndexes([0], byExtendingSelection: false)
        resizeAndPosition()
        if !panel.isVisible { panel.orderFront(nil) }
    }

    private func resizeAndPosition() {
        guard let tv = textView, let window = tv.window else { return }
        let rows = min(matches.count, maxRows)
        let h = CGFloat(rows) * (rowH + 1) + 8
        let w: CGFloat = 320

        // Caret rect → screen coordinates, panel just below.
        let glyphRange = NSRange(location: max(0, triggerStart - 2), length: 0)
        var rectInView = tv.firstRect(forCharacterRange: glyphRange, actualRange: nil)
        if rectInView == .zero {
            rectInView = NSRect(origin: window.frame.origin, size: .zero)
            panel.setFrame(NSRect(x: rectInView.minX, y: rectInView.minY, width: w, height: h), display: true)
            return
        }
        let x = rectInView.minX
        let y = rectInView.minY - h - 4
        panel.setFrame(NSRect(x: x, y: y, width: w, height: h), display: true)
    }

    // MARK: Keyboard (called by the editor's doCommandBy)

    func moveSelection(_ delta: Int) {
        guard !matches.isEmpty else { return }
        let next = max(0, min(matches.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    @discardableResult
    func commit() -> Bool {
        guard isActive, let tv = textView else { return false }
        let row = tableView.selectedRow
        guard row >= 0, row < matches.count else { return false }
        let caret = tv.selectedRange().location
        let replaceRange = NSRange(location: triggerStart, length: max(0, caret - triggerStart))
        tv.insertText(matches[row] + "]]", replacementRange: replaceRange)
        dismiss()
        return true
    }

    func dismiss() { if panel.isVisible { panel.orderOut(nil) } }

    @objc private func rowClicked() {
        if tableView.clickedRow >= 0 {
            tableView.selectRowIndexes([tableView.clickedRow], byExtendingSelection: false)
            commit()
            textView?.window?.makeFirstResponder(textView)
        }
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { matches.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        CompleterRowView()
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("WLCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView) ?? {
            let c = NSTableCellView()
            let tf = NSTextField(labelWithString: "")
            tf.translatesAutoresizingMaskIntoConstraints = false
            tf.lineBreakMode = .byTruncatingTail
            tf.font = NSFont.systemFont(ofSize: 12.5)
            c.addSubview(tf); c.textField = tf
            NSLayoutConstraint.activate([
                tf.leadingAnchor.constraint(equalTo: c.leadingAnchor, constant: 10),
                tf.trailingAnchor.constraint(equalTo: c.trailingAnchor, constant: -10),
                tf.centerYAnchor.constraint(equalTo: c.centerYAnchor),
            ])
            c.identifier = id
            return c
        }()
        cell.textField?.stringValue = matches[row]
        return cell
    }
}

private final class CompleterRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let r = bounds.insetBy(dx: 3, dy: 0)
        Theme.accent.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: r, xRadius: 5, yRadius: 5).fill()
    }
}
