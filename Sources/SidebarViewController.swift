import AppKit

/// A custom two-line cell: bold title, secondary snippet, tertiary date.
final class NoteCell: NSTableCellView, NSTextFieldDelegate {
    let titleField = NSTextField(labelWithString: "")
    let snippetField = NSTextField(labelWithString: "")
    let dateField = NSTextField(labelWithString: "")

    /// Called when an inline rename commits with a new name.
    var onRename: ((String) -> Void)?

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return f
    }()

    override init(frame: NSRect) {
        super.init(frame: frame)
        for f in [titleField, snippetField, dateField] {
            f.translatesAutoresizingMaskIntoConstraints = false
            f.lineBreakMode = .byTruncatingTail
            f.maximumNumberOfLines = 1
            f.cell?.usesSingleLineMode = true
            addSubview(f)
        }
        titleField.font = Theme.titleFont
        titleField.textColor = Theme.primaryText
        titleField.delegate = self
        titleField.focusRingType = .none
        titleField.isBordered = false
        titleField.drawsBackground = false
        titleField.isEditable = false

        snippetField.font = Theme.snippetFont
        snippetField.textColor = Theme.secondaryText

        dateField.font = Theme.dateFont
        dateField.textColor = Theme.tertiaryText

        NSLayoutConstraint.activate([
            titleField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            titleField.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            titleField.topAnchor.constraint(equalTo: topAnchor, constant: 9),

            snippetField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            snippetField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            snippetField.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 3),

            dateField.leadingAnchor.constraint(equalTo: titleField.leadingAnchor),
            dateField.trailingAnchor.constraint(equalTo: titleField.trailingAnchor),
            dateField.topAnchor.constraint(equalTo: snippetField.bottomAnchor, constant: 3),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(_ meta: NoteMeta) {
        titleField.stringValue = meta.title
        snippetField.stringValue = meta.snippet.isEmpty ? "No additional text" : meta.snippet
        snippetField.textColor = meta.snippet.isEmpty ? Theme.tertiaryText : Theme.secondaryText
        dateField.stringValue = Self.dateFormatter.string(from: meta.modified)
    }

    func beginRename() {
        titleField.isEditable = true
        titleField.isBordered = true
        titleField.drawsBackground = true
        titleField.backgroundColor = .textBackgroundColor
        window?.makeFirstResponder(titleField)
        titleField.selectText(nil)
    }

    private func endRename() {
        titleField.isEditable = false
        titleField.isBordered = false
        titleField.drawsBackground = false
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        let newName = titleField.stringValue
        endRename()
        onRename?(newName)
    }
}

final class SidebarViewController: NSViewController,
                                  NSTableViewDataSource, NSTableViewDelegate,
                                  NSSearchFieldDelegate {

    var store: NotesStore!
    var onSelect: ((NoteMeta?) -> Void)?

    private let searchField = NSSearchField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private var selectedURL: URL?
    private var suppressCallback = false
    private var searchDebounce: DispatchWorkItem?

    override func loadView() {
        let container = NSView()

        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.placeholderString = "Search notes"
        searchField.delegate = self
        searchField.sendsWholeSearchString = false
        searchField.focusRingType = .none
        searchField.bezelStyle = .roundedBezel
        container.addSubview(searchField)

        tableView.headerView = nil
        tableView.style = .sourceList
        tableView.rowHeight = Theme.rowHeight
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = NSSize(width: 0, height: 2)
        tableView.dataSource = self
        tableView.delegate = self
        tableView.target = self
        tableView.doubleAction = #selector(handleDoubleClick)
        let col = NSTableColumn(identifier: .init("note"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        container.addSubview(scrollView)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 8),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),

            scrollView.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    // MARK: Public

    /// Reload rows, keeping the current selection (by URL) without firing onSelect.
    func refresh() {
        tableView.reloadData()
        if let url = selectedURL, let row = store.notes.firstIndex(where: { $0.url == url }) {
            suppressCallback = true
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            suppressCallback = false
        } else if selectedURL != nil, store.notes.first(where: { $0.url == selectedURL }) == nil {
            // Selected note is filtered out by search — clear table selection but
            // leave the editor showing it.
            suppressCallback = true
            tableView.deselectAll(nil)
            suppressCallback = false
        }
    }

    /// Programmatically select a note (e.g. after New, or open-from-Finder).
    func select(_ url: URL?, loadIt: Bool) {
        selectedURL = url
        tableView.reloadData()
        if let url, let row = store.notes.firstIndex(where: { $0.url == url }) {
            suppressCallback = true
            tableView.selectRowIndexes([row], byExtendingSelection: false)
            tableView.scrollRowToVisible(row)
            suppressCallback = false
        }
        if loadIt { onSelect?(url.flatMap { store.meta(for: $0) }) }
    }

    func focusSearch() { view.window?.makeFirstResponder(searchField) }

    /// Set the search box programmatically (e.g. clicking a #tag in the editor).
    func setSearch(_ text: String) {
        searchDebounce?.cancel()
        searchField.stringValue = text
        store.query = text
        view.window?.makeFirstResponder(searchField)
    }

    // MARK: Search

    func controlTextDidChange(_ obj: Notification) {
        guard obj.object as? NSSearchField === searchField else { return }
        let value = searchField.stringValue
        searchDebounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.store.query = value }
        searchDebounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: work)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if control === searchField, selector == #selector(NSResponder.moveDown(_:)), !store.notes.isEmpty {
            view.window?.makeFirstResponder(tableView)
            tableView.selectRowIndexes([0], byExtendingSelection: false)
            return true
        }
        return false
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { store?.notes.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("NoteCell")
        let cell = (tableView.makeView(withIdentifier: id, owner: self) as? NoteCell) ?? {
            let c = NoteCell(frame: .zero); c.identifier = id; return c
        }()
        let meta = store.notes[row]
        cell.configure(meta)
        cell.onRename = { [weak self] newName in
            guard let self else { return }
            let url = meta.url
            if newName == meta.title || newName.trimmingCharacters(in: .whitespaces).isEmpty {
                self.tableView.reloadData(); return
            }
            if let newURL = self.store.rename(url, toBaseName: newName) {
                self.selectedURL = newURL
                self.refresh()
                self.onSelect?(self.store.meta(for: newURL))
            } else {
                NSSound.beep()
                self.refresh()
            }
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        SidebarRowView()
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !suppressCallback else { return }
        let row = tableView.selectedRow
        if row >= 0, row < store.notes.count {
            selectedURL = store.notes[row].url
            onSelect?(store.notes[row])
        }
    }

    @objc private func handleDoubleClick() {
        let row = tableView.clickedRow
        guard row >= 0, let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? NoteCell else { return }
        cell.beginRename()
    }
}

/// Soft verdigris "pill" selection — the brand accent, matching the command
/// palette, instead of the system blue source-list highlight.
private final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard isSelected else { return }
        let r = bounds.insetBy(dx: 8, dy: 2)
        Theme.accent.withAlphaComponent(0.20).setFill()
        NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
    }
}
