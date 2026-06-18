import AppKit

/// Central place for everything visual. One file to retune the whole look.
enum Theme {

    // MARK: Editor typography
    static var editorFont: NSFont {
        NSFont.systemFont(ofSize: 16, weight: .regular)
    }
    static let editorLineSpacing: CGFloat = 7
    static let editorParagraphSpacing: CGFloat = 12
    static let editorColumnWidth: CGFloat = 680      // readable measure, centered
    static let editorMinSideInset: CGFloat = 32
    static let editorTopInset: CGFloat = 22          // added on top of the toolbar inset

    static var monoFont: NSFont {
        NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)
    }

    // MARK: Sidebar
    static let sidebarMinWidth: CGFloat = 230
    static let sidebarMaxWidth: CGFloat = 460
    static let rowHeight: CGFloat = 62

    static var titleFont: NSFont { NSFont.systemFont(ofSize: 13.5, weight: .semibold) }
    static var snippetFont: NSFont { NSFont.systemFont(ofSize: 12, weight: .regular) }
    static var dateFont: NSFont { NSFont.systemFont(ofSize: 11, weight: .regular) }

    // MARK: Colors (semantic → automatic light/dark + vibrancy)
    static var editorText: NSColor { .labelColor }
    static var editorBackground: NSColor { .textBackgroundColor }
    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }

    // MARK: Brand palette — Ink + Copper
    // Everything is ink on paper. ONE accent: copper, the warm metal beneath the
    // patina. It marks only what's interactive/alive (caret, selection, links).
    // Code syntax uses a restrained set of aged-metal tones — copper, bronze,
    // brass, oxblood — never the overused teal/blue/purple.
    static func tone(_ light: (CGFloat, CGFloat, CGFloat), _ dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { ap in
            let c = ap.isDark ? dark : light
            return NSColor(calibratedRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }
    static var copper: NSColor { tone((0.71, 0.38, 0.12), (0.88, 0.60, 0.34)) }   // #B5611F / #E0995 7
    static var accent: NSColor { copper }

    // MARK: Syntax (live editor styling)
    static var syntaxMarker: NSColor { .tertiaryLabelColor }   // dimmed #, **, ` etc.
    static var codeColor: NSColor { copper }                   // inline `code` in Markdown
    static let headerSizes: [CGFloat] = [27, 23, 20, 17, 16, 15]

    // MARK: Code token colors (json / yaml / env)
    // Copper is the brand accent (keys); the rest are spaced far apart in hue AND
    // value so tokens read at a glance — olive (strings), gold (numbers), oxblood
    // (keywords). Earthy, but clearly distinct — no teal/blue/purple.
    static var codeKey: NSColor       { copper }                                       // keys → copper accent
    static var codeString: NSColor    { tone((0.34, 0.47, 0.17), (0.67, 0.81, 0.47)) } // olive / sage green
    static var codeNumber: NSColor    { tone((0.60, 0.47, 0.06), (0.90, 0.78, 0.44)) } // brass / gold
    static var codeKeyword: NSColor   { tone((0.73, 0.20, 0.15), (0.93, 0.47, 0.41)) } // oxblood
    static var codeComment: NSColor   { .tertiaryLabelColor }
    static var codePunctuation: NSColor { .secondaryLabelColor }
    static var monoCodeFont: NSFont   { NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular) }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// An NSTextView that keeps text in a centered, fixed-width column for
/// comfortable reading — the typographic heart of the editor.
final class CenteringTextView: NSTextView {
    var columnWidth: CGFloat = Theme.editorColumnWidth
    var minSideInset: CGFloat = Theme.editorMinSideInset
    var topInset: CGFloat = Theme.editorTopInset

    /// Called when the user clicks a `.link`-attributed character. We handle this
    /// ourselves because an editable NSTextView does NOT fire `clickedOnLink` on a
    /// plain click — it just moves the caret.
    var onLinkClick: ((URL) -> Void)?

    enum ColumnMode {
        case leftCapped   // prose: hug the left margin, wrap at a readable width
        case full         // code: hug the left margin, use the whole width
    }
    var columnMode: ColumnMode = .leftCapped { didSet { applyColumnMode() } }

    /// Always left-aligned at `minSideInset`; the only difference is whether the
    /// line length is capped (prose) or fills the pane (code).
    func applyColumnMode() {
        guard let tc = textContainer else { return }
        switch columnMode {
        case .full:
            tc.widthTracksTextView = true
        case .leftCapped:
            tc.widthTracksTextView = false
            tc.size = NSSize(width: columnWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        isHorizontallyResizable = false
        textContainerInset = NSSize(width: minSideInset, height: topInset)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1 {
            let p = convert(event.locationInWindow, from: nil)
            if let url = linkURL(at: p) {
                onLinkClick?(url)
                return   // don't fall through to caret placement
            }
        }
        super.mouseDown(with: event)
    }

    /// Resolve the `.link` URL under a point in *view* coordinates, or nil.
    /// Factored out of `mouseDown` so the hit-testing can be tested headlessly.
    func linkURL(at point: NSPoint) -> URL? {
        guard let lm = layoutManager, let tc = textContainer,
              let ts = textStorage, ts.length > 0 else { return nil }
        var p = point
        p.x -= textContainerOrigin.x
        p.y -= textContainerOrigin.y
        var frac: CGFloat = 0
        let glyph = lm.glyphIndex(for: p, in: tc, fractionOfDistanceThroughGlyph: &frac)
        guard glyph < lm.numberOfGlyphs else { return nil }
        // Make sure the click actually landed on the glyph, not past a line end.
        let box = lm.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: tc)
        guard box.contains(p) else { return nil }
        let charIdx = lm.characterIndexForGlyph(at: glyph)
        guard charIdx < ts.length,
              let value = ts.attribute(.link, at: charIdx, effectiveRange: nil) else { return nil }
        return (value as? URL) ?? (value as? String).flatMap { URL(string: $0) }
    }
}
