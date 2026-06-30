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
            ensureFolderStructure(at: url)
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

            #if os(macOS)
            // A bookmark minted while the app only had read-only file access keeps
            // granting read-only even after the entitlement becomes read-write.
            // If we can't actually write, drop the bookmark so the app re-prompts
            // for the folder and mints a fresh read-write bookmark.
            guard isWritable(url) else {
                print("Journal root resolved but is not writable; clearing bookmark to re-prompt for folder selection.")
                url.stopAccessingSecurityScopedResource()
                UserDefaults.standard.removeObject(forKey: bookmarkKey)
                return
            }
            #endif

            journalRoot = url
            ensureFolderStructure(at: url)

            #if os(macOS)
            if isStale,
               let fresh = try? url.bookmarkData(
                   options: .withSecurityScope,
                   includingResourceValuesForKeys: nil,
                   relativeTo: nil
               ) {
                UserDefaults.standard.set(fresh, forKey: bookmarkKey)
            }
            #endif
            print("Journal root is writable: \(url.path)")
        } catch {
            print("Failed to resolve stored journal root: \(error)")
        }
    }

    /// Probes whether the app can actually create a file under the journal root.
    /// Used to detect a stale read-only security-scoped bookmark.
    private func isWritable(_ root: URL) -> Bool {
        let fm = FileManager.default
        let dir = root.appendingPathComponent(".journal", isDirectory: true)
        let probe = dir.appendingPathComponent(".writeprobe")
        do {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try "ok".write(to: probe, atomically: true, encoding: .utf8)
            try? fm.removeItem(at: probe)
            return true
        } catch {
            return false
        }
    }

    private func ensureFolderStructure(at root: URL) {
        // Best-effort: never throw here. The journal often lives on a cloud
        // volume (iCloud, ProtonDrive, …) where creating a not-yet-existing
        // folder can fail with "Operation not permitted". A failure must not
        // abort resolving the root or poison writes for the rest of the session.
        let fm = FileManager.default
        for sub in ["entries", "images", "media", "attachments", "imports/raw", ".journal"] {
            try? fm.createDirectory(
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

    func mediaDir(for entry: JournalEntry, subfolder: String) -> URL? {
        guard let root = journalRoot else { return nil }
        let (year, month) = routingPath(for: entry)
        return root.appendingPathComponent(
            "\(subfolder)/\(year)/\(month)/\(entry.id)",
            isDirectory: true
        )
    }

    func attachmentsDir(for entry: JournalEntry) -> URL? {
        mediaDir(for: entry, subfolder: "images")
    }

    /// Copies a file into the entry's folder under `subfolder` (`images` for
    /// pictures, `media` for audio/video) and returns the journal-relative path.
    func copyAttachment(from source: URL, for entry: JournalEntry, subfolder: String = "images") throws -> String {
        guard let dir = mediaDir(for: entry, subfolder: subfolder) else { throw StoreError.notConfigured }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = uniqueDestination(in: dir, filename: source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: dest)
        let (year, month) = routingPath(for: entry)
        return "\(subfolder)/\(year)/\(month)/\(entry.id)/\(dest.lastPathComponent)"
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

    /// Changes an entry's date. Because the on-disk path is routed by the
    /// created date (year/month), this re-saves at the new location and removes
    /// the old file. The entry's `id` is kept stable as its identity.
    func reschedule(_ entry: JournalEntry, to newDate: Date) -> JournalEntry {
        let oldURL = fileURL(for: entry)
        var updated = entry
        updated.created = newDate
        updated.modified = Date()
        do {
            try save(updated)
            if let oldURL, let newURL = fileURL(for: updated),
               oldURL.standardizedFileURL != newURL.standardizedFileURL,
               FileManager.default.fileExists(atPath: oldURL.path) {
                try? FileManager.default.removeItem(at: oldURL)
                refreshEntries()
            }
        } catch {
            print("Reschedule failed: \(error)")
        }
        return updated
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
