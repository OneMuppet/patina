import AppKit

// Headless tests for Patina's pure logic (no window server needed).
// Run via tests/run.sh. Exits non-zero on any failure (used by CI).

var fails = 0
func check(_ cond: Bool, _ msg: String) {
    print((cond ? "PASS" : "FAIL") + ": " + msg)
    if !cond { fails += 1 }
}

func tmpDir() -> String {
    let d = NSTemporaryDirectory() + "patina-tests-" + UUID().uuidString
    try! FileManager.default.createDirectory(atPath: d, withIntermediateDirectories: true)
    return d
}

// MARK: FileKind
func k(_ p: String) -> FileKind { FileKind.of(URL(fileURLWithPath: p)) }
check(k("/a/b.md") == .markdown, "FileKind: .md → markdown")
check(k("/a/b.json") == .json, "FileKind: .json → json")
check(k("/a/b.yaml") == .yaml && k("/a/c.yml") == .yaml, "FileKind: .yaml/.yml → yaml")
check(k("/a/.env") == .env && k("/a/.env.local") == .env && k("/a/prod.env") == .env, "FileKind: env variants")
check(k("/a/n.txt") == .plainText, "FileKind: .txt → plainText")
check(k("/a/x.conf") == .code, "FileKind: unknown → code")

// MARK: Code highlighting — tokens get distinct, resolvable colors
func rgba(_ c: NSColor?) -> [Int] {
    guard let c else { return [-1] }
    var out = [0, 0, 0]
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
        if let s = c.usingColorSpace(.sRGB) {
            out = [Int(s.redComponent * 255), Int(s.greenComponent * 255), Int(s.blueComponent * 255)]
        }
    }
    return out
}
func fg(_ ts: NSTextStorage, _ s: String, _ needle: String) -> [Int] {
    let r = (s as NSString).range(of: needle)
    return rgba(ts.attribute(.foregroundColor, at: r.location, effectiveRange: nil) as? NSColor)
}
let js = "{\n  \"name\": \"Bob\",\n  \"age\": 30,\n  \"ok\": true\n}"
let jts = NSTextStorage(string: js)
CodeHighlighter.highlight(jts, range: NSRange(location: 0, length: jts.length), kind: .json)
let toks = Set([fg(jts, js, "name"), fg(jts, js, "Bob"), fg(jts, js, "30"), fg(jts, js, "true")].map { "\($0)" })
check(toks.count == 4, "JSON key/string/number/keyword are 4 distinct colors")
_ = { CodeHighlighter.highlight(NSTextStorage(string: "k: \"v😀\" # c\n#full\n- 1"),
        range: NSRange(location: 0, length: 9), kind: .yaml) }()  // emoji/edge: no crash
check(true, "YAML highlight on emoji/edge did not crash")

// MARK: Markdown live styling — wiki-links + tags become decodable links
func links(_ s: String) -> [(String, String)] {
    let ts = NSTextStorage(string: s)
    SyntaxHighlighter.highlight(ts, range: NSRange(location: 0, length: ts.length))
    var out: [(String, String)] = []
    ts.enumerateAttribute(.link, in: NSRange(location: 0, length: ts.length)) { v, _, _ in
        if let u = v as? URL, let d = SyntaxHighlighter.decodeLink(u) { out.append((d.scheme, d.payload)) }
    }
    return out
}
let wl = links("see [[My Note]] and #project here")
check(wl.contains { $0 == (SyntaxHighlighter.noteScheme, "My Note") }, "wiki-link decodes to 'My Note'")
check(wl.contains { $0 == (SyntaxHighlighter.tagScheme, "project") }, "tag decodes to 'project'")
check(links("# Heading").isEmpty, "'# Heading' is not a tag/link")
_ = links("**b😀** [[e 😀 n]] #t😀") ; check(true, "emoji markdown did not crash")

// MARK: NotesStore — canonicalization, backlinks, mutations (under a symlinked dir)
let real = "/private" + tmpDir()        // ensure symlink divergence like /tmp → /private/tmp
try! FileManager.default.createDirectory(atPath: real, withIntermediateDirectories: true)
func w(_ n: String, _ b: String) { try! b.data(using: .utf8)!.write(to: URL(fileURLWithPath: real + "/" + n)) }
w("Hub.md", "# Hub"); w("A.md", "links [[Hub]]"); w("B.md", "also [[Hub]] and [[A]]")
let store = NotesStore()
store.setFolder(URL(fileURLWithPath: real.replacingOccurrences(of: "/private", with: "")))  // open via the /tmp-style path
let hub = store.note(withTitle: "Hub")!
store.save("# Hub edited", to: hub.url)
check(store.notes.filter { $0.title == "Hub" }.count == 1, "save does not duplicate row (canonical URLs)")
check(store.backlinks(toTitle: "Hub", excluding: hub.url).map { $0.title }.sorted() == ["A", "B"], "backlinks(Hub) = [A,B]")
let created = store.createNamedNote("Fresh")
check(created != nil && store.createNamedNote("Fresh") == created, "createNamedNote is idempotent")
let aURL = store.note(withTitle: "A")!.url
let trash = store.deleteNote(aURL)
check(trash != nil && store.note(withTitle: "A") == nil, "delete removes note + returns trash url")
check(store.restore(from: trash!, to: aURL) != nil && store.note(withTitle: "A") != nil, "restore brings it back")

// MARK: LibraryIndex — record/search/fuzzy/prune/persistence (HOME is temp in run.sh)
let idxDir = tmpDir()
let f1 = URL(fileURLWithPath: idxDir + "/Ideas.md"); try! "x".write(to: f1, atomically: true, encoding: .utf8)
let idx = LibraryIndex()
idx.record(f1, title: "Ideas", opened: true)
check(idx.search("ides").first?.title == "Ideas", "fuzzy 'ides' → Ideas")
let idx2 = LibraryIndex()
check(idx2.search("").contains { $0.title == "Ideas" }, "index persists across instances")
try! FileManager.default.removeItem(at: f1)
check(idx2.prune() == 1 && !idx2.search("").contains { $0.title == "Ideas" }, "prune drops the deleted file")

print(fails == 0 ? "\nALL GREEN ✅" : "\n\(fails) FAILURE(S) ❌")
exit(fails == 0 ? 0 : 1)
