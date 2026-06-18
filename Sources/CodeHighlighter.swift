import AppKit

/// What kind of file we're showing — decides how it's styled and whether the
/// Markdown viewer / wiki-links apply.
enum FileKind {
    case markdown, plainText, json, yaml, env, code

    static func of(_ url: URL?) -> FileKind {
        guard let url else { return .plainText }
        let name = url.lastPathComponent.lowercased()
        if name == ".env" || name.hasPrefix(".env.") { return .env }
        switch url.pathExtension.lowercased() {
        case "md", "markdown", "mdown", "markdn", "mdwn", "mkd": return .markdown
        case "json": return .json
        case "yaml", "yml": return .yaml
        case "env": return .env
        case "txt", "text", "": return .plainText
        default: return .code
        }
    }

    var isMarkdown: Bool { self == .markdown }
}

/// Syntax highlighting for structured/code files. Same approach as the Markdown
/// highlighter: reset a range to base attributes, then colour tokens. Cheap
/// enough to run per-edited-paragraph on every keystroke.
enum CodeHighlighter {

    static func highlight(_ ts: NSTextStorage, range: NSRange, kind: FileKind) {
        let safe = NSIntersectionRange(range, NSRange(location: 0, length: ts.length))
        guard safe.length > 0 else { return }
        ts.setAttributes(base(), range: safe)
        switch kind {
        case .json: json(ts, safe)
        case .yaml: yaml(ts, safe)
        case .env:  env(ts, safe)
        default: break
        }
    }

    static func base() -> [NSAttributedString.Key: Any] {
        let p = NSMutableParagraphStyle()
        p.lineSpacing = 3
        return [.font: Theme.monoCodeFont, .foregroundColor: Theme.editorText, .paragraphStyle: p]
    }

    // MARK: JSON

    private static func json(_ ts: NSTextStorage, _ range: NSRange) {
        let s = ts.string as NSString
        let n = range.location + range.length
        var i = range.location
        func ch(_ k: Int) -> unichar { s.character(at: k) }
        while i < n {
            let c = ch(i)
            switch c {
            case 34: // "  → string; if followed by ':' it's a key
                let start = i
                i += 1
                while i < n {
                    let d = ch(i)
                    if d == 92 { i += 2; continue }       // escape
                    if d == 34 { i += 1; break }
                    i += 1
                }
                var j = i
                while j < n, ch(j) == 32 || ch(j) == 9 { j += 1 }
                let isKey = j < n && ch(j) == 58 // ':'
                color(ts, start, i - start, isKey ? Theme.codeKey : Theme.codeString)
            case 48...57, 45: // number / -
                let start = i
                while i < n, isNumberChar(ch(i)) { i += 1 }
                color(ts, start, i - start, Theme.codeNumber)
                continue
            case 123, 125, 91, 93, 44, 58: // { } [ ] , :
                color(ts, i, 1, Theme.codePunctuation); i += 1
            case 116, 102, 110: // t f n  → true/false/null
                let start = i
                while i < n, isWordChar(ch(i)) { i += 1 }
                let w = s.substring(with: NSRange(location: start, length: i - start))
                if w == "true" || w == "false" || w == "null" { color(ts, start, i - start, Theme.codeKeyword) }
                continue
            default:
                i += 1
            }
        }
    }

    // MARK: YAML

    private static func yaml(_ ts: NSTextStorage, _ range: NSRange) {
        let s = ts.string as NSString
        s.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = s.substring(with: lineRange) as NSString
            let n = line.length
            var i = 0
            while i < n, line.character(at: i) == 32 { i += 1 }   // indent
            guard i < n else { return }
            // full-line comment
            if line.character(at: i) == 35 {
                color(ts, lineRange.location + i, n - i, Theme.codeComment); return
            }
            // list marker "- "
            if line.character(at: i) == 45, i + 1 <= n, (i + 1 == n || line.character(at: i + 1) == 32) {
                color(ts, lineRange.location + i, 1, Theme.codePunctuation)
                i += 1
            }
            // key: value
            var colon = -1
            var k = i
            while k < n {
                let c = line.character(at: k)
                if c == 58, k + 1 == n || line.character(at: k + 1) == 32 { colon = k; break }
                if c == 35 { break }
                k += 1
            }
            if colon >= 0 {
                color(ts, lineRange.location + i, colon - i, Theme.codeKey)
                color(ts, lineRange.location + colon, 1, Theme.codePunctuation)
                styleValue(ts, line: line, base: lineRange.location, from: colon + 1, to: n)
            } else {
                styleValue(ts, line: line, base: lineRange.location, from: i, to: n)
            }
        }
    }

    // MARK: .env

    private static func env(_ ts: NSTextStorage, _ range: NSRange) {
        let s = ts.string as NSString
        s.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = s.substring(with: lineRange) as NSString
            let n = line.length
            var i = 0
            while i < n, line.character(at: i) == 32 { i += 1 }
            guard i < n else { return }
            if line.character(at: i) == 35 {
                color(ts, lineRange.location + i, n - i, Theme.codeComment); return
            }
            // optional "export "
            let rest = line.substring(from: i)
            if rest.hasPrefix("export ") {
                color(ts, lineRange.location + i, 6, Theme.codeKeyword)
                i += 7
            }
            // KEY=VALUE
            var eq = -1
            var k = i
            while k < n { if line.character(at: k) == 61 { eq = k; break }; k += 1 } // '='
            if eq >= 0 {
                color(ts, lineRange.location + i, eq - i, Theme.codeKey)
                color(ts, lineRange.location + eq, 1, Theme.codePunctuation)
                styleValue(ts, line: line, base: lineRange.location, from: eq + 1, to: n)
            }
        }
    }

    /// Colour a scalar value: quoted → string, numeric → number, bool/null → keyword.
    private static func styleValue(_ ts: NSTextStorage, line: NSString, base: Int, from: Int, to: Int) {
        var a = from
        while a < to, line.character(at: a) == 32 { a += 1 }
        guard a < to else { return }
        // trailing inline comment
        var end = to
        var c = a
        while c < to {
            if line.character(at: c) == 35, c > a, line.character(at: c - 1) == 32 {
                color(ts, base + c, to - c, Theme.codeComment); end = c
                break
            }
            c += 1
        }
        while end > a, line.character(at: end - 1) == 32 { end -= 1 }
        guard end > a else { return }
        let token = line.substring(with: NSRange(location: a, length: end - a))
        let first = line.character(at: a)
        if first == 34 || first == 39 {           // quoted string
            color(ts, base + a, end - a, Theme.codeString)
        } else if isNumeric(token) {
            color(ts, base + a, end - a, Theme.codeNumber)
        } else if ["true", "false", "null", "yes", "no", "~"].contains(token.lowercased()) {
            color(ts, base + a, end - a, Theme.codeKeyword)
        }
    }

    // MARK: helpers

    private static func isNumberChar(_ c: unichar) -> Bool {
        (c >= 48 && c <= 57) || c == 45 || c == 43 || c == 46 || c == 101 || c == 69
    }
    private static func isWordChar(_ c: unichar) -> Bool {
        (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
    }
    private static func isNumeric(_ s: String) -> Bool {
        guard !s.isEmpty else { return false }
        return Double(s) != nil
    }
    private static func color(_ ts: NSTextStorage, _ loc: Int, _ len: Int, _ c: NSColor) {
        guard len > 0, loc >= 0, loc + len <= ts.length else { return }
        ts.addAttribute(.foregroundColor, value: c, range: NSRange(location: loc, length: len))
    }
}
