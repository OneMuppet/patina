import AppKit

/// Lightweight live Markdown styling applied directly to the editor's text.
/// Per-line + inline scanning (fast enough to run on every keystroke over the
/// edited paragraph). Syntax markers are dimmed so the prose stands out — the
/// "premium editor" feel without rendering the text away.
enum SyntaxHighlighter {

    static func baseAttributes() -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = Theme.editorLineSpacing
        p.paragraphSpacing = Theme.editorParagraphSpacing
        return [.font: Theme.editorFont, .foregroundColor: Theme.editorText, .paragraphStyle: p]
    }

    static func highlight(_ ts: NSTextStorage, range: NSRange) {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ts.length))
        guard safe.length > 0 else { return }
        ts.setAttributes(baseAttributes(), range: safe)
        let full = ts.string as NSString
        var fenceLang: FileKind?     // non-nil while inside a ``` block
        full.enumerateSubstrings(in: safe, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let trimmed = full.substring(with: lineRange).trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                // Fence line: dim it, and toggle in/out of a code block.
                setFont(ts, lineRange.location, lineRange.length, Theme.monoFont)
                dim(ts, lineRange.location, lineRange.length)
                if fenceLang == nil {
                    fenceLang = fenceKind(String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces))
                } else {
                    fenceLang = nil
                }
                return
            }
            if let lang = fenceLang {
                if lang == .code {
                    if lineRange.length > 0 {
                        ts.setAttributes(CodeHighlighter.base(), range: lineRange)
                    }
                } else {
                    CodeHighlighter.highlight(ts, range: lineRange, kind: lang)
                }
            } else {
                styleLine(ts, lineRange: lineRange, full: full)
            }
        }
    }

    /// Map a fenced-code-block language tag to a highlighter kind.
    private static func fenceKind(_ tag: String) -> FileKind {
        switch tag.lowercased() {
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "env", "dotenv": return .env
        default: return .code
        }
    }

    // MARK: Per-line

    private static let hash = unichar(35), gt = unichar(62), space = unichar(32)
    private static let star = unichar(42), under = unichar(95), tick = unichar(96)
    private static let lbrack = unichar(91), rbrack = unichar(93)
    private static let lparen = unichar(40), rparen = unichar(41)
    private static let dash = unichar(45), plus = unichar(43)
    private static let slash = unichar(47)

    /// Custom URL schemes used for clickable wiki-links and tags in the editor.
    static let noteScheme = "patina-note"
    static let tagScheme = "patina-tag"

    private static func styleLine(_ ts: NSTextStorage, lineRange: NSRange, full: NSString) {
        guard lineRange.length > 0 else { return }
        let line = full.substring(with: lineRange) as NSString
        let n = line.length

        // ATX headings: #..###### followed by a space
        var h = 0
        while h < n && line.character(at: h) == hash { h += 1 }
        if h >= 1, h <= 6, h < n, line.character(at: h) == space {
            let size = Theme.headerSizes[h - 1]
            ts.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: size), range: lineRange)
            color(ts, lineRange.location, h + 1, Theme.syntaxMarker)
            return
        }

        // Blockquote
        if n >= 1, line.character(at: 0) == gt {
            color(ts, lineRange.location, lineRange.length, Theme.secondaryText)
            let mlen = (n >= 2 && line.character(at: 1) == space) ? 2 : 1
            color(ts, lineRange.location, mlen, Theme.syntaxMarker)
        }
        // Bullet list marker
        else if n >= 2, isBullet(line.character(at: 0)), line.character(at: 1) == space {
            color(ts, lineRange.location, 1, Theme.accent)
        }

        applyInline(ts, lineRange: lineRange, line: line)
    }

    private static func isBullet(_ c: unichar) -> Bool { c == dash || c == star || c == plus }

    // MARK: Inline spans

    private static func applyInline(_ ts: NSTextStorage, lineRange: NSRange, line: NSString) {
        let n = line.length
        let baseFont = Theme.editorFont
        var i = 0
        func ch(_ k: Int) -> unichar { line.character(at: k) }
        func isWordChar(_ k: Int) -> Bool {
            guard k >= 0, k < n else { return false }
            let c = ch(k)
            return (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
        }
        func find(_ target: unichar, from: Int) -> Int? {
            var k = from; while k < n { if ch(k) == target { return k }; k += 1 }; return nil
        }
        func findDouble(_ target: unichar, from: Int) -> Int? {
            var k = from; while k + 1 < n { if ch(k) == target && ch(k+1) == target { return k }; k += 1 }; return nil
        }

        while i < n {
            let c = ch(i)
            // inline code
            if c == tick, let close = find(tick, from: i + 1) {
                setFont(ts, lineRange.location + i + 1, close - (i + 1), Theme.monoFont)
                color(ts, lineRange.location + i + 1, close - (i + 1), Theme.codeColor)
                dim(ts, lineRange.location + i, 1); dim(ts, lineRange.location + close, 1)
                i = close + 1; continue
            }
            // bold ** **
            if c == star, i + 1 < n, ch(i + 1) == star, let close = findDouble(star, from: i + 2) {
                setFont(ts, lineRange.location + i + 2, close - (i + 2),
                        NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask))
                dim(ts, lineRange.location + i, 2); dim(ts, lineRange.location + close, 2)
                i = close + 2; continue
            }
            // italic * * / _ _ (underscore only at word boundaries, to spare snake_case)
            if c == star || c == under {
                let boundaryOK = c == star || (!isWordChar(i - 1))
                if boundaryOK, let close = find(c, from: i + 1), close > i + 1,
                   (c == star || !isWordChar(close + 1)) {
                    setFont(ts, lineRange.location + i + 1, close - (i + 1),
                            NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask))
                    dim(ts, lineRange.location + i, 1); dim(ts, lineRange.location + close, 1)
                    i = close + 1; continue
                }
            }
            // wiki-link [[Note Name]]
            if c == lbrack, i + 1 < n, ch(i + 1) == lbrack, let close = findDouble(rbrack, from: i + 2), close > i + 2 {
                let nameLoc = lineRange.location + i + 2
                let nameLen = close - (i + 2)
                color(ts, nameLoc, nameLen, Theme.accent)
                underline(ts, nameLoc, nameLen)
                link(ts, nameLoc, nameLen, scheme: noteScheme, payload: line.substring(with: NSRange(location: i + 2, length: nameLen)))
                dim(ts, lineRange.location + i, 2)
                dim(ts, lineRange.location + close, 2)
                i = close + 2; continue
            }
            // link [text](url)
            if c == lbrack, let cb = find(rbrack, from: i + 1), cb + 1 < n, ch(cb + 1) == lparen,
               let cp = find(rparen, from: cb + 2) {
                color(ts, lineRange.location + i + 1, cb - (i + 1), Theme.accent)
                dim(ts, lineRange.location + i, 1)
                dim(ts, lineRange.location + cb, cp - cb + 1)
                i = cp + 1; continue
            }
            // #tag (at a word boundary, followed by tag chars; not a heading)
            if c == hash, i + 1 < n, isTagChar(ch(i + 1)),
               i == 0 || (!isWordChar(i - 1) && ch(i - 1) != hash) {
                var end = i + 1
                while end < n, isTagChar(ch(end)) { end += 1 }
                let tag = line.substring(with: NSRange(location: i + 1, length: end - (i + 1)))
                color(ts, lineRange.location + i, end - i, Theme.accent)
                link(ts, lineRange.location + i, end - i, scheme: tagScheme, payload: tag)
                i = end; continue
            }
            i += 1
        }
    }

    // MARK: Attribute helpers

    private static func color(_ ts: NSTextStorage, _ loc: Int, _ len: Int, _ c: NSColor) {
        guard len > 0 else { return }
        ts.addAttribute(.foregroundColor, value: c, range: NSRange(location: loc, length: len))
    }
    private static func dim(_ ts: NSTextStorage, _ loc: Int, _ len: Int) {
        color(ts, loc, len, Theme.syntaxMarker)
    }
    private static func setFont(_ ts: NSTextStorage, _ loc: Int, _ len: Int, _ f: NSFont) {
        guard len > 0 else { return }
        ts.addAttribute(.font, value: f, range: NSRange(location: loc, length: len))
    }
    private static func underline(_ ts: NSTextStorage, _ loc: Int, _ len: Int) {
        guard len > 0 else { return }
        ts.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue,
                        range: NSRange(location: loc, length: len))
    }
    private static func link(_ ts: NSTextStorage, _ loc: Int, _ len: Int, scheme: String, payload: String) {
        guard len > 0 else { return }
        let enc = payload.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? payload
        guard let url = URL(string: "\(scheme):\(enc)") else { return }
        ts.addAttribute(.link, value: url, range: NSRange(location: loc, length: len))
    }
    private static func isTagChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
            || c == under || c == dash || c == slash
    }

    /// Decode a clicked link URL back into (scheme, payload). Used by the editor.
    static func decodeLink(_ url: URL) -> (scheme: String, payload: String)? {
        guard let scheme = url.scheme, scheme == noteScheme || scheme == tagScheme else { return nil }
        let raw = String(url.absoluteString.dropFirst(scheme.count + 1))
        return (scheme, raw.removingPercentEncoding ?? raw)
    }
}
