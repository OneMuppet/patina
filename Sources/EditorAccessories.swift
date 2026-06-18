import AppKit

/// A slim notification bar shown at the top of the editor (file-conflict,
/// undo-delete, …). Collapses when hidden inside an NSStackView.
final class BannerView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let buttonStack = NSStackView()
    private var dismissWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = Theme.accent.withAlphaComponent(0.14).cgColor
        isHidden = true

        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.translatesAutoresizingMaskIntoConstraints = false
        buttonStack.orientation = .horizontal
        buttonStack.spacing = 8
        addSubview(label)
        addSubview(buttonStack)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            buttonStack.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
            buttonStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            buttonStack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Show with a message and up to a few inline actions; optional auto-dismiss.
    func show(_ message: String, actions: [(title: String, handler: () -> Void)],
              autoDismiss: TimeInterval? = nil) {
        label.stringValue = message
        buttonStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for action in actions {
            let b = NSButton(title: action.title, target: nil, action: nil)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.actionBlock = action.handler
            b.target = b
            b.action = #selector(NSButton.fireActionBlock)
            buttonStack.addArrangedSubview(b)
        }
        isHidden = false
        dismissWork?.cancel()
        if let t = autoDismiss {
            let work = DispatchWorkItem { [weak self] in self?.dismiss() }
            dismissWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + t, execute: work)
        }
    }

    func dismiss() {
        dismissWork?.cancel()
        isHidden = true
    }
}

private var actionBlockKey: UInt8 = 0
extension NSButton {
    var actionBlock: (() -> Void)? {
        get { objc_getAssociatedObject(self, &actionBlockKey) as? (() -> Void) }
        set { objc_setAssociatedObject(self, &actionBlockKey, newValue, .OBJC_ASSOCIATION_RETAIN) }
    }
    @objc func fireActionBlock() { actionBlock?() }
}

/// "Linked from …" strip — notes that wiki-link to the current one. Collapses
/// when there are no backlinks.
final class BacklinksBar: NSView {
    var onSelect: ((URL) -> Void)?
    private let caption = NSTextField(labelWithString: "Linked from")
    private let stack = NSStackView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true

        let top = NSBox(); top.boxType = .separator
        top.translatesAutoresizingMaskIntoConstraints = false
        addSubview(top)

        caption.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
        caption.textColor = .tertiaryLabelColor
        caption.translatesAutoresizingMaskIntoConstraints = false
        addSubview(caption)

        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        let scroll = NSScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        let doc = NSView()
        doc.translatesAutoresizingMaskIntoConstraints = false
        doc.addSubview(stack)
        scroll.documentView = doc
        addSubview(scroll)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 34),
            top.topAnchor.constraint(equalTo: topAnchor),
            top.leadingAnchor.constraint(equalTo: leadingAnchor),
            top.trailingAnchor.constraint(equalTo: trailingAnchor),
            caption.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            caption.centerYAnchor.constraint(equalTo: centerYAnchor),
            scroll.leadingAnchor.constraint(equalTo: caption.trailingAnchor, constant: 10),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            scroll.centerYAnchor.constraint(equalTo: centerYAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 24),
            stack.leadingAnchor.constraint(equalTo: doc.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: doc.trailingAnchor),
            stack.centerYAnchor.constraint(equalTo: doc.centerYAnchor),
            doc.heightAnchor.constraint(equalTo: scroll.heightAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }

    func set(_ items: [(title: String, url: URL)]) {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        for item in items {
            let b = NSButton(title: item.title, target: nil, action: nil)
            b.isBordered = false
            b.contentTintColor = Theme.accent
            b.font = NSFont.systemFont(ofSize: 11, weight: .medium)
            let url = item.url
            b.actionBlock = { [weak self] in self?.onSelect?(url) }
            b.target = b
            b.action = #selector(NSButton.fireActionBlock)
            stack.addArrangedSubview(b)
        }
        isHidden = items.isEmpty
    }
}
