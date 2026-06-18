import Foundation

/// A persistent index of every note Patina has ever seen — across all folders
/// you've opened and every file opened directly. Backs the Command Palette so
/// you can jump to any remembered note instantly. Stored as JSON in Application
/// Support and self-healing: missing files are pruned on load and on demand.
final class LibraryIndex {

    struct Entry: Codable {
        var path: String
        var title: String
        var lastOpened: Date
        var url: URL { URL(fileURLWithPath: path) }
    }

    private(set) var entries: [Entry] = []
    private let fileURL: URL

    init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = support.appendingPathComponent("Patina", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("library.json")
        load()
        prune()
    }

    // MARK: Recording

    /// Record (or refresh) a note. `opened: true` bumps its lastOpened to now so
    /// it floats to the top of recents; `false` just registers it as known.
    func record(_ rawURL: URL, title: String, opened: Bool) {
        let url = NotesStore.canonical(rawURL)
        if let i = entries.firstIndex(where: { $0.path == url.path }) {
            entries[i].title = title
            if opened { entries[i].lastOpened = Date() }
        } else {
            entries.append(Entry(path: url.path, title: title, lastOpened: opened ? Date() : Date.distantPast))
        }
        save()
    }

    /// Bulk-register every note in a freshly opened folder (without bumping recency).
    func registerFolder(_ notes: [NoteMeta]) {
        for n in notes {
            if !entries.contains(where: { $0.path == n.url.path }) {
                entries.append(Entry(path: n.url.path, title: n.title, lastOpened: Date.distantPast))
            } else if let i = entries.firstIndex(where: { $0.path == n.url.path }) {
                entries[i].title = n.title
            }
        }
        save()
    }

    func remove(_ rawURL: URL) {
        let path = NotesStore.canonical(rawURL).path
        entries.removeAll { $0.path == path }
        save()
    }

    func rename(from oldURL: URL, to newURL: URL, title: String) {
        remove(oldURL)
        record(newURL, title: title, opened: true)
    }

    // MARK: Querying

    /// Recents-first, optionally fuzzy-filtered. Drops any file that vanished.
    func search(_ query: String) -> [Entry] {
        let live = entries.filter { FileManager.default.fileExists(atPath: $0.path) }
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let matched: [Entry]
        if q.isEmpty {
            matched = live
        } else {
            matched = live.filter { Self.fuzzy(q, in: $0.title.lowercased()) || $0.path.lowercased().contains(q) }
        }
        return matched.sorted { $0.lastOpened > $1.lastOpened }
    }

    /// Subsequence fuzzy match: "ides" matches "Ideas".
    static func fuzzy(_ needle: String, in haystack: String) -> Bool {
        if needle.isEmpty { return true }
        if haystack.contains(needle) { return true }
        var it = haystack.makeIterator()
        for ch in needle {
            var found = false
            while let h = it.next() { if h == ch { found = true; break } }
            if !found { return false }
        }
        return true
    }

    // MARK: Persistence

    @discardableResult
    func prune() -> Int {
        let before = entries.count
        entries.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
        if entries.count != before { save() }
        return before - entries.count
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
