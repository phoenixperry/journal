import Foundation
import Observation

@Observable
@MainActor
final class JournalStore {
    private(set) var journalRoot: URL?
    private(set) var entries: [JournalEntry] = []

    private let bookmarkKey = "JournalRootBookmark"

    init() {
        loadStoredRoot()
        refreshEntries()
    }

    var isConfigured: Bool { journalRoot != nil }

    func setJournalRoot(_ url: URL) {
        do {
            #if os(macOS)
            let bookmark = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #else
            let bookmark = try url.bookmarkData(
                options: [],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            #endif
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            journalRoot = url
            try ensureFolderStructure(at: url)
            refreshEntries()
        } catch {
            print("Failed to store journal root: \(error)")
        }
    }

    private func loadStoredRoot() {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return }
        do {
            var isStale = false
            #if os(macOS)
            let url = try URL(
                resolvingBookmarkData: data,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            _ = url.startAccessingSecurityScopedResource()
            #else
            let url = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            #endif
            journalRoot = url
            try ensureFolderStructure(at: url)
        } catch {
            print("Failed to resolve stored journal root: \(error)")
        }
    }

    private func ensureFolderStructure(at root: URL) throws {
        let fm = FileManager.default
        for sub in ["entries", "attachments", "imports/raw", ".journal"] {
            try fm.createDirectory(
                at: root.appendingPathComponent(sub),
                withIntermediateDirectories: true
            )
        }
    }

    func fileURL(for entry: JournalEntry) -> URL? {
        guard let root = journalRoot else { return nil }
        let (year, month) = routingPath(for: entry)
        return root
            .appendingPathComponent("entries/\(year)/\(month)", isDirectory: true)
            .appendingPathComponent("\(entry.id).md")
    }

    func attachmentsDir(for entry: JournalEntry) -> URL? {
        guard let root = journalRoot else { return nil }
        let (year, month) = routingPath(for: entry)
        return root.appendingPathComponent(
            "attachments/\(year)/\(month)/\(entry.id)",
            isDirectory: true
        )
    }

    func copyAttachment(from source: URL, for entry: JournalEntry) throws -> String {
        guard let dir = attachmentsDir(for: entry) else { throw StoreError.notConfigured }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: dir, filename: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)
        let (year, month) = routingPath(for: entry)
        return "attachments/\(year)/\(month)/\(entry.id)/\(dest.lastPathComponent)"
    }

    private func routingPath(for entry: JournalEntry) -> (year: String, month: String) {
        let comps = Calendar.current.dateComponents([.year, .month], from: entry.created)
        return (
            String(format: "%04d", comps.year ?? 0),
            String(format: "%02d", comps.month ?? 0)
        )
    }

    private func uniqueDestination(in dir: URL, filename: String) -> URL {
        let fm = FileManager.default
        let initial = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: initial.path) { return initial }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        while true {
            let suffix = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            let candidate = dir.appendingPathComponent(suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    func save(_ entry: JournalEntry) throws {
        guard let url = fileURL(for: entry) else { throw StoreError.notConfigured }
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FrontmatterCodec.encode(entry).write(to: url, atomically: true, encoding: .utf8)
        clearRecovery(for: entry)
        refreshEntries()
    }

    func writeRecovery(_ entry: JournalEntry) {
        guard !entry.body.isEmpty, let dir = recoveryDir() else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(entry.id).md")
        try? FrontmatterCodec.encode(entry).write(to: url, atomically: true, encoding: .utf8)
    }

    func clearRecovery(for entry: JournalEntry) {
        guard let dir = recoveryDir() else { return }
        let url = dir.appendingPathComponent("\(entry.id).md")
        try? FileManager.default.removeItem(at: url)
    }

    func pendingRecoveries() -> [JournalEntry] {
        guard let dir = recoveryDir() else { return [] }
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return []
        }
        var results: [JournalEntry] = []
        for url in urls where url.pathExtension == "md" {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let entry = FrontmatterCodec.decode(text) else { continue }
            if let savedURL = fileURL(for: entry),
               let savedText = try? String(contentsOf: savedURL, encoding: .utf8),
               let savedEntry = FrontmatterCodec.decode(savedText),
               savedEntry.modified >= entry.modified {
                try? fm.removeItem(at: url)
                continue
            }
            results.append(entry)
        }
        return results.sorted { $0.modified > $1.modified }
    }

    private func recoveryDir() -> URL? {
        journalRoot?.appendingPathComponent(".journal/recovery", isDirectory: true)
    }

    func delete(_ entry: JournalEntry) throws {
        guard let url = fileURL(for: entry) else { throw StoreError.notConfigured }
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.trashItem(at: url, resultingItemURL: nil)
        }
        refreshEntries()
    }

    func refreshEntries() {
        guard let root = journalRoot else {
            entries = []
            return
        }
        let entriesDir = root.appendingPathComponent("entries", isDirectory: true)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: entriesDir,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            entries = []
            return
        }

        var loaded: [JournalEntry] = []
        for case let url as URL in enumerator where url.pathExtension == "md" {
            if let text = try? String(contentsOf: url, encoding: .utf8),
               let entry = FrontmatterCodec.decode(text) {
                loaded.append(entry)
            }
        }
        entries = loaded.sorted { $0.created > $1.created }
    }

    enum StoreError: Error {
        case notConfigured
    }
}
