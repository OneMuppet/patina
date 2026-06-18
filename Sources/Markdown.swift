import AppKit

/// A small, dependency-free Markdown → NSAttributedString renderer.
/// Line-based for blocks, scanner-based for inline spans. Fast and predictable —
/// no WebView, no HTML, so the preview costs almost nothing to show.
enum Markdown {

    private static let bodySize: CGFloat = 15

    static func render(_ markdown: String) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = markdown.components(separatedBy: "\n")

        var inFence = false
        var fenceBuffer: [String] = []

        func flushFence() {
            let code = fenceBuffer.joined(separator: "\n")
            out.append(codeBlock(code))
            out.append(NSAttributedString(string: "\n"))
            fenceBuffer.removeAll()
        }

        for rawLine in lines {
            let line = rawLine
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code blocks ```
            if trimmed.hasPrefix("```") {
                if inFence { flushFence(); inFence = false }
                else { inFence = true }
                continue
            }
            if inFence { fenceBuffer.append(line); continue }

            // Blank line → paragraph gap
            if trimmed.isEmpty {
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Horizontal rule
            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                out.append(horizontalRule())
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Headings #..######
            if let h = heading(trimmed) {
                out.append(h)
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Blockquote >
            if trimmed.hasPrefix(">") {
                let content = String(trimmed.drop(while: { $0 == ">" || $0 == " " }))
                out.append(blockquote(content))
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Unordered list - * +
            if let bulletContent = unorderedItem(trimmed) {
                out.append(listItem(marker: "•  ", content: bulletContent))
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Ordered list 1. 2. ...
            if let (num, content) = orderedItem(trimmed) {
                out.append(listItem(marker: "\(num).  ", content: content))
                out.append(NSAttributedString(string: "\n"))
                continue
            }

            // Plain paragraph
            let para = inline(Substring(line), font: bodyFont(), color: .textColor)
            let m = NSMutableAttributedString(attributedString: para)
            m.addAttribute(.paragraphStyle, value: bodyParagraph(), range: NSRange(location: 0, length: m.length))
            out.append(m)
            out.append(NSAttributedString(string: "\n"))
        }
        if inFence { flushFence() }
        return out
    }

    // MARK: - Block builders

    private static func bodyFont() -> NSFont { NSFont.systemFont(ofSize: bodySize) }

    private static func bodyParagraph() -> NSParagraphStyle {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 6
        p.lineSpacing = 2
        return p
    }

    private static func heading(_ line: String) -> NSAttributedString? {
        var level = 0
        for ch in line { if ch == "#" { level += 1 } else { break } }
        guard level >= 1, level <= 6 else { return nil }
        let rest = line.dropFirst(level)
        guard rest.first == " " else { return nil }
        let text = rest.drop(while: { $0 == " " })

        let sizes: [CGFloat] = [28, 23, 19, 16, 15, 14]
        let size = sizes[level - 1]
        let font = NSFont.boldSystemFont(ofSize: size)
        let attr = NSMutableAttributedString(attributedString: inline(text, font: font, color: .labelColor))
        let p = NSMutableParagraphStyle()
        p.paragraphSpacingBefore = level <= 2 ? 12 : 8
        p.paragraphSpacing = 4
        attr.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private static func codeBlock(_ code: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 10
        p.headIndent = 10
        p.paragraphSpacing = 6
        return NSAttributedString(string: code, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .backgroundColor: NSColor.quaternaryLabelColor,
            .paragraphStyle: p,
        ])
    }

    private static func blockquote(_ content: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 16
        p.headIndent = 16
        p.paragraphSpacing = 6
        let font = NSFontManager.shared.convert(bodyFont(), toHaveTrait: .italicFontMask)
        let attr = NSMutableAttributedString(attributedString: inline(Substring(content), font: font, color: .secondaryLabelColor))
        attr.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private static func listItem(marker: String, content: String) -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.firstLineHeadIndent = 18
        p.headIndent = 34
        p.paragraphSpacing = 3
        let attr = NSMutableAttributedString()
        attr.append(NSAttributedString(string: marker, attributes: [.font: bodyFont(), .foregroundColor: NSColor.secondaryLabelColor]))
        attr.append(inline(Substring(content), font: bodyFont(), color: .textColor))
        attr.addAttribute(.paragraphStyle, value: p, range: NSRange(location: 0, length: attr.length))
        return attr
    }

    private static func horizontalRule() -> NSAttributedString {
        let p = NSMutableParagraphStyle()
        p.paragraphSpacing = 6
        return NSAttributedString(string: "________________________", attributes: [
            .font: NSFont.systemFont(ofSize: bodySize),
            .foregroundColor: NSColor.tertiaryLabelColor,
            .paragraphStyle: p,
        ])
    }

    private static func unorderedItem(_ line: String) -> String? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return String(line.dropFirst(prefix.count))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> (Int, String)? {
        var digits = ""
        var idx = line.startIndex
        while idx < line.endIndex, line[idx].isNumber { digits.append(line[idx]); idx = line.index(after: idx) }
        guard !digits.isEmpty, idx < line.endIndex, line[idx] == "." else { return nil }
        let after = line.index(after: idx)
        guard after < line.endIndex, line[after] == " " else { return nil }
        let content = String(line[line.index(after: after)...])
        return (Int(digits) ?? 0, content)
    }

    // MARK: - Inline scanner: `code`, **bold**, *italic*/_italic_, [text](url)

    private static func inline(_ line: Substring, font: NSFont, color: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(line)
        var i = 0
        var plain = ""

        func flush() {
            if !plain.isEmpty {
                result.append(NSAttributedString(string: plain, attributes: [.font: font, .foregroundColor: color]))
                plain = ""
            }
        }
        func find(_ ch: Character, from: Int) -> Int? {
            var j = from
            while j < chars.count { if chars[j] == ch { return j }; j += 1 }
            return nil
        }
        func findPair(from: Int) -> Int? {
            var j = from
            while j + 1 < chars.count { if chars[j] == "*" && chars[j+1] == "*" { return j }; j += 1 }
            return nil
        }

        while i < chars.count {
            let c = chars[i]

            // inline code
            if c == "`", let close = find("`", from: i + 1) {
                flush()
                let codeStr = String(chars[(i + 1)..<close])
                result.append(NSAttributedString(string: codeStr, attributes: [
                    .font: NSFont.monospacedSystemFont(ofSize: font.pointSize - 1, weight: .regular),
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.quaternaryLabelColor,
                ]))
                i = close + 1; continue
            }

            // bold **...**
            if c == "*", i + 1 < chars.count, chars[i + 1] == "*", let close = findPair(from: i + 2) {
                flush()
                let inner = String(chars[(i + 2)..<close])
                let boldFont = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
                result.append(inline(Substring(inner), font: boldFont, color: color))
                i = close + 2; continue
            }

            // italic *...* or _..._
            if (c == "*" || c == "_"), let close = find(c, from: i + 1), close > i + 1 {
                flush()
                let inner = String(chars[(i + 1)..<close])
                let itFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
                result.append(inline(Substring(inner), font: itFont, color: color))
                i = close + 1; continue
            }

            // link [text](url)
            if c == "[", let closeB = find("]", from: i + 1),
               closeB + 1 < chars.count, chars[closeB + 1] == "(",
               let closeP = find(")", from: closeB + 2) {
                flush()
                let textStr = String(chars[(i + 1)..<closeB])
                let urlStr = String(chars[(closeB + 2)..<closeP])
                result.append(NSAttributedString(string: textStr, attributes: [
                    .font: font,
                    .foregroundColor: NSColor.linkColor,
                    .link: urlStr,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]))
                i = closeP + 1; continue
            }

            plain.append(c)
            i += 1
        }
        flush()
        return result
    }
}
