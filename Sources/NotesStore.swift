import AppKit

struct NoteMeta: Equatable {
    let url: URL
    var title: String      // file name without extension
    var snippet: String    // first line of real content
    var modified: Date

    static func == (a: NoteMeta, b: NoteMeta) -> Bool { a.url == b.url }
}

/// The model: owns the current folder, scans it for notes, runs search, and
/// keeps the list live via a folder watcher. All mutation happens on the main
/// thread (UI-driven), so no locking is needed.
final class NotesStore {

    static let extensions: Set<String> =
        ["md", "markdown", "mdown", "markdn", "mdwn", "mkd", "txt", "text",
         "json", "yaml", "yml", "env", "toml", "ini", "conf", "cfg", "xml", "csv", "log"]

    private(set) var folder: URL?
    private(set) var allNotes: [NoteMeta] = []
    private(set) var notes: [NoteMeta] = []        // filtered + sorted (newest first)

    var query: String = "" {
        didSet { if query != oldValue { rebuildFiltered() } }
    }

    /// Called whenever `notes` changes. Wired to the sidebar.
    var onChange: (() -> Void)?

    private var watcher: FolderWatcher?
    private var contentCache: [URL: (mtime: Date, size: Int, text: String)] = [:]
    private var lastSelfSave = Date.distantPast

    /// Canonical form so URLs from `contentsOfDirectory` (symlink-resolved, e.g.
    /// `/private/tmp/…`) compare equal to ones we build from the folder path
    /// (e.g. `/tmp/…`). `standardizedFileURL` does the heavy lifting here — it
    /// collapses the `/private` prefix so both sides converge; `resolvingSymlinksInPath`
    /// additionally follows any symlinked components. Every URL entering the store
    /// passes through this so `NoteMeta.==`, selection, and persistence all line up.
    static func canonical(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    // MARK: Folder

    func setFolder(_ url: URL?) {
        watcher?.stop()
        watcher = nil
        let canon = url.map(Self.canonical)
        folder = canon
        contentCache.removeAll()
        if let canon {
            watcher = FolderWatcher(url: canon) { [weak self] in
                guard let self else { return }
                // Ignore the echo of our own autosave to avoid needless rescans.
                if Date().timeIntervalSince(self.lastSelfSave) < 1.0 { return }
                self.scan()
            }
            watcher?.start()
        }
        scan()
    }

    // MARK: Scanning

    func scan() {
        guard let folder else {
            allNotes = []; notes = []; onChange?(); return
        }
        // Drop cached content: an external edit may keep mtime+size identical, so
        // a fresh scan is the safe moment to forget what we think files contain.
        contentCache.removeAll()
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .isRegularFileKey]
        var result: [NoteMeta] = []
        if let items = try? FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]) {
            for u in items {
                let cu = Self.canonical(u)
                guard Self.extensions.contains(cu.pathExtension.lowercased()) else { continue }
                let vals = try? cu.resourceValues(forKeys: keys)
                if vals?.isRegularFile == false { continue }
                let mod = vals?.contentModificationDate ?? Date.distantPast
                let (title, snippet) = Self.preview(of: cu)
                result.append(NoteMeta(url: cu, title: title, snippet: snippet, modified: mod))
            }
        }
        allNotes = result
        rebuildFiltered()
    }

    private func rebuildFiltered() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var list = allNotes
        if !q.isEmpty {
            list = allNotes.filter { meta in
                if meta.title.lowercased().contains(q) { return true }
                if meta.snippet.lowercased().contains(q) { return true }
                return content(of: meta.url).lowercased().contains(q)
            }
        }
        list.sort { $0.modified > $1.modified }
        notes = list
        onChange?()
    }

    // MARK: Content (cached for search)
    //
    // Freshness is guaranteed primarily by `scan()` calling `contentCache.removeAll()`:
    // every external-edit entry point (the folder watcher) routes through `scan()`,
    // so the cache is wiped before any search re-reads. The `(mtime, size)` key below
    // is a secondary guard — note that an atomic write (temp-file + rename) may not
    // advance mtime, so the key alone would not catch a same-size atomic edit; the
    // scan-time clear is what actually defends against stale search results.

    func content(of url: URL) -> String {
        let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mtime = vals?.contentModificationDate ?? Date.distantPast
        let size = vals?.fileSize ?? -1
        if let cached = contentCache[url], cached.mtime == mtime, cached.size == size {
            return cached.text
        }
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        contentCache[url] = (mtime, size, text)
        return text
    }

    // MARK: Mutations

    func save(_ text: String, to rawURL: URL) {
        let url = Self.canonical(rawURL)
        lastSelfSave = Date()
        try? text.data(using: .utf8)?.write(to: url, options: .atomic)
        let vals = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let mtime = vals?.contentModificationDate ?? Date()
        let size = vals?.fileSize ?? Data(text.utf8).count
        contentCache[url] = (mtime, size, text)
        refreshMeta(url)
    }

    func createNote() -> URL? {
        guard let folder else { return nil }
        let fm = FileManager.default
        var base = "Untitled"
        var url = folder.appendingPathComponent(base + ".md")
        var n = 2
        while fm.fileExists(atPath: url.path) {
            base = "Untitled \(n)"
            url = folder.appendingPathComponent(base + ".md")
            n += 1
        }
        guard (try? Data().write(to: url)) != nil else { return nil }
        lastSelfSave = Date()
        scan()
        return Self.canonical(url)
    }

    /// Move a note to the Trash. Returns the resulting Trash URL so the deletion
    /// can be undone with `restore(from:to:)`.
    @discardableResult
    /// Create a note with a specific title (used when a `[[link]]` points at a
    /// note that doesn't exist yet). Returns the existing file if already present.
    func createNamedNote(_ title: String) -> URL? {
        guard let folder else { return nil }
        let safe = title.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !safe.isEmpty else { return nil }
        let url = folder.appendingPathComponent(safe + ".md")
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "# \(safe)\n".data(using: .utf8)?.write(to: url)
        }
        lastSelfSave = Date()
        scan()
        return Self.canonical(url)
    }

    @discardableResult
    func deleteNote(_ rawURL: URL) -> URL? {
        let url = Self.canonical(rawURL)
        var trashURL: NSURL?
        try? FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
        contentCache[url] = nil
        scan()
        return trashURL as URL?
    }

    /// Restore a trashed note back to its original location.
    @discardableResult
    func restore(from trashURL: URL, to originalRawURL: URL) -> URL? {
        let original = Self.canonical(originalRawURL)
        guard (try? FileManager.default.moveItem(at: trashURL, to: original)) != nil else { return nil }
        lastSelfSave = Date()
        scan()
        return original
    }

    /// Rename a note's file to a new base name (extension preserved).
    /// Returns the new URL, or nil if the name was invalid or already taken.
    func rename(_ rawURL: URL, toBaseName raw: String) -> URL? {
        guard let folder else { return nil }
        let url = Self.canonical(rawURL)
        let base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        guard !base.isEmpty else { return nil }
        let ext = url.pathExtension.isEmpty ? "md" : url.pathExtension
        let newURL = Self.canonical(folder.appendingPathComponent(base + "." + ext))
        if newURL == url { return url }
        if FileManager.default.fileExists(atPath: newURL.path) { return nil }
        guard (try? FileManager.default.moveItem(at: url, to: newURL)) != nil else { return nil }
        if let c = contentCache[url] { contentCache[newURL] = c; contentCache[url] = nil }
        lastSelfSave = Date()
        scan()
        return newURL
    }

    func meta(for rawURL: URL) -> NoteMeta? {
        let url = Self.canonical(rawURL)
        return notes.first { $0.url == url } ?? allNotes.first { $0.url == url }
    }

    /// Notes whose text contains a `[[title]]` wiki-link to the given title.
    func backlinks(toTitle title: String, excluding: URL?) -> [NoteMeta] {
        let needle = "[[\(title)]]".lowercased()
        guard !title.isEmpty else { return [] }
        return allNotes
            .filter { $0.url != excluding && content(of: $0.url).lowercased().contains(needle) }
            .sorted { $0.modified > $1.modified }
    }

    /// Find an existing note by its title (filename without extension).
    func note(withTitle title: String) -> NoteMeta? {
        allNotes.first { $0.title.compare(title, options: .caseInsensitive) == .orderedSame }
    }

    // MARK: Helpers

    private func refreshMeta(_ url: URL) {
        let mod = (try? url.resourceValues(forKeys: [.contentModificationDateKey])
            .contentModificationDate) ?? Date()
        let (title, snippet) = Self.preview(of: url)
        let m = NoteMeta(url: url, title: title, snippet: snippet, modified: mod)
        if let i = allNotes.firstIndex(where: { $0.url == url }) { allNotes[i] = m }
        else { allNotes.append(m) }
        rebuildFiltered()
    }

    /// (title, snippet) without reading the whole file — first ~4 KB is plenty.
    private static func preview(of url: URL) -> (String, String) {
        let title = url.deletingPathExtension().lastPathComponent
        var snippet = ""
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            let text = String(decoding: data.prefix(4096), as: UTF8.self)
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.isEmpty { continue }
                let clean = t.drop(while: { $0 == "#" || $0 == ">" || $0 == " " })
                if !clean.isEmpty { snippet = String(clean); break }
            }
        }
        return (title, snippet)
    }
}
