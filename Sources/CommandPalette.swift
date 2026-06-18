import AppKit

/// Borderless panel that can still take keyboard focus (for the search field).
final class PalettePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A Spotlight-style quick-open palette over the whole library index.
/// ⌘K → type to fuzzy-filter every remembered note → ↑/↓ → Enter to open.
final class CommandPaletteController: NSObject, NSTableViewDataSource, NSTableViewDelegate,
                                      NSSearchFieldDelegate, NSWindowDelegate {

    private let index: LibraryIndex
    private let onChoose: (URL) -> Void

    private var panel: PalettePanel!
    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private var results: [LibraryIndex.Entry] = []

    private let width: CGFloat = 580
    private let rowH: CGFloat = 46
    private let headerH: CGFloat = 56
    private let maxRows = 8

    init(index: LibraryIndex, onChoose: @escaping (URL) -> Void) {
        self.index = index
        self.onChoose = onChoose
        super.init()
        build()
    }

    // MARK: Build

    private func build() {
        let vfx = NSVisualEffectView()
        vfx.material = .menu
        vfx.blendingMode = .behindWindow
        vfx.state = .active
        vfx.wantsLayer = true
        vfx.layer?.cornerRadius = 12
        vfx.layer?.masksToBounds = true

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Quick open…"
        searchField.font = NSFont.systemFont(ofSize: 20, weight: .regular)
        searchField.focusRingType = .none
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.delegate = self
        (searchField.cell as? NSSearchFieldCell)?.searchButtonCell?.image =
            NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: nil)
        vfx.addSubview(searchField)

        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.style = .plain
        tableView.rowHeight = rowH
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.selectionHighlightStyle = .regular
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.action = #selector(rowClicked)
        tableView.addTableColumn(NSTableColumn(identifier: .init("c")))

        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = tableView
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.borderType = .noBorder
        vfx.addSubview(scroll)

        let divider = NSBox()
        divider.boxType = .separator
        divider.translatesAutoresizingMaskIntoConstraints = false
        vfx.addSubview(divider)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: vfx.topAnchor, constant: 12),
            searchField.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 18),
            searchField.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -18),

            divider.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 12),
            divider.leadingAnchor.constraint(equalTo: vfx.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: vfx.trailingAnchor),

            scroll.topAnchor.constraint(equalTo: divider.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: vfx.leadingAnchor, constant: 6),
            scroll.trailingAnchor.constraint(equalTo: vfx.trailingAnchor, constant: -6),
            scroll.bottomAnchor.constraint(equalTo: vfx.bottomAnchor, constant: -6),
        ])

        panel = PalettePanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 360),
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .modalPanel
        panel.isMovable = false
        panel.delegate = self
        panel.contentView = vfx
    }

    // MARK: Show / hide

    func toggle(over parent: NSWindow?) {
        if panel.isVisible { close() } else { show(over: parent) }
    }

    func show(over parent: NSWindow?) {
        searchField.stringValue = ""
        reload(query: "")
        resize()
        if let parent {
            let pf = parent.frame
            let x = pf.midX - width / 2
            let y = pf.midY + pf.height * 0.10
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else {
            panel.center()
        }
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(searchField)
    }

    func close() { panel.orderOut(nil) }

    func windowDidResignKey(_ notification: Notification) { close() }

    private func resize() {
        let visible = min(results.count, maxRows)
        let listH = CGFloat(max(visible, 1)) * (rowH + 2) + 10
        let h = headerH + listH
        var frame = panel.frame
        frame.origin.y += frame.height - h   // keep top edge anchored
        frame.size = NSSize(width: width, height: h)
        panel.setFrame(frame, display: true)
    }

    private func reload(query: String) {
        results = index.search(query)
        tableView.reloadData()
        if !results.isEmpty { tableView.selectRowIndexes([0], byExtendingSelection: false) }
    }

    private func choose() {
        let row = tableView.selectedRow
        guard row >= 0, row < results.count else { return }
        let url = results[row].url
        close()
        onChoose(url)
    }

    @objc private func rowClicked() {
        if tableView.clickedRow >= 0 { choose() }
    }

    // MARK: Search field keyboard handling

    func controlTextDidChange(_ obj: Notification) {
        reload(query: searchField.stringValue)
        resize()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.moveDown(_:)):
            move(by: 1); return true
        case #selector(NSResponder.moveUp(_:)):
            move(by: -1); return true
        case #selector(NSResponder.insertNewline(_:)):
            choose(); return true
        case #selector(NSResponder.cancelOperation(_:)):
            close(); return true
        default:
            return false
        }
    }

    private func move(by delta: Int) {
        guard !results.isEmpty else { return }
        let next = max(0, min(results.count - 1, tableView.selectedRow + delta))
        tableView.selectRowIndexes([next], byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("PaletteCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? PaletteCell) ?? {
            let c = PaletteCell(); c.identifier = id; return c
        }()
        let e = results[row]
        cell.title.stringValue = e.title
        cell.subtitle.stringValue = e.url.deletingLastPathComponent().lastPathComponent
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        PaletteRowView()
    }
}

/// Rounded accent selection for palette rows.
private final class PaletteRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let r = bounds.insetBy(dx: 6, dy: 1)
        Theme.accent.withAlphaComponent(0.22).setFill()
        NSBezierPath(roundedRect: r, xRadius: 7, yRadius: 7).fill()
    }
}

private final class PaletteCell: NSTableCellView {
    let title = NSTextField(labelWithString: "")
    let subtitle = NSTextField(labelWithString: "")

    init() {
        super.init(frame: .zero)
        title.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        subtitle.font = NSFont.systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingMiddle
        for f in [title, subtitle] { f.translatesAutoresizingMaskIntoConstraints = false; addSubview(f) }
        NSLayoutConstraint.activate([
            title.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            title.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            title.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            subtitle.leadingAnchor.constraint(equalTo: title.leadingAnchor),
            subtitle.trailingAnchor.constraint(equalTo: title.trailingAnchor),
            subtitle.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 2),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
