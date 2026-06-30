import SwiftUI

#if os(macOS)
import AppKit
import ImageIO
#endif

struct EntryListView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let currentEntryID: String
    let onSelect: (JournalEntry) -> Void
    let onNew: () -> Void
    let onDeleted: (JournalEntry) -> Void

    @State private var pendingDelete: JournalEntry?

    var body: some View {
        List {
            Section {
                Button(action: onNew) {
                    Label("New Entry", systemImage: "square.and.pencil")
                }
                .buttonStyle(.plain)
                .keyboardShortcut("n", modifiers: .command)
            }

            ForEach(groupedEntries, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.entries) { entry in
                        EntryRow(
                            entry: entry,
                            isSelected: entry.id == currentEntryID,
                            accent: settings.accentColor,
                            journalRoot: store.journalRoot
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(
                            entry.id == currentEntryID
                                ? settings.accentColor.opacity(0.25)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                pendingDelete = entry
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                pendingDelete = entry
                            } label: {
                                Label("Delete…", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Journal")
        .confirmationDialog(
            confirmationTitle,
            isPresented: deleteBinding,
            presenting: pendingDelete
        ) { entry in
            Button("Delete", role: .destructive) {
                performDelete(entry)
            }
            Button("Cancel", role: .cancel) {
                pendingDelete = nil
            }
        } message: { entry in
            Text(confirmationMessage(for: entry))
        }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        )
    }

    private var confirmationTitle: String {
        "Delete this entry?"
    }

    private func confirmationMessage(for entry: JournalEntry) -> String {
        let dateStr = entry.created.formatted(date: .abbreviated, time: .shortened)
        return "\(dateStr) will be moved to the Trash. You can restore it from there if you change your mind."
    }

    private func performDelete(_ entry: JournalEntry) {
        do {
            try store.delete(entry)
            onDeleted(entry)
        } catch {
            print("Delete failed: \(error)")
        }
        pendingDelete = nil
    }

    private var groupedEntries: [EntryGroup] {
        let cal = Calendar.current
        let now = Date()
        let today = cal.startOfDay(for: now)
        let weekAgo = cal.date(byAdding: .day, value: -7, to: today)!
        let monthAgo = cal.date(byAdding: .day, value: -30, to: today)!

        var todayEntries: [JournalEntry] = []
        var weekEntries: [JournalEntry] = []
        var monthEntries: [JournalEntry] = []
        var olderEntries: [JournalEntry] = []

        for entry in store.entries {
            let day = cal.startOfDay(for: entry.created)
            if day >= today { todayEntries.append(entry) }
            else if day >= weekAgo { weekEntries.append(entry) }
            else if day >= monthAgo { monthEntries.append(entry) }
            else { olderEntries.append(entry) }
        }

        var groups: [EntryGroup] = []
        if !todayEntries.isEmpty { groups.append(.init(label: "Today", entries: todayEntries)) }
        if !weekEntries.isEmpty { groups.append(.init(label: "Past Week", entries: weekEntries)) }
        if !monthEntries.isEmpty { groups.append(.init(label: "Past Month", entries: monthEntries)) }
        if !olderEntries.isEmpty { groups.append(.init(label: "Older", entries: olderEntries)) }
        return groups
    }

    struct EntryGroup {
        let label: String
        let entries: [JournalEntry]
    }
}

private struct EntryRow: View {
    let entry: JournalEntry
    let isSelected: Bool
    let accent: Color
    let journalRoot: URL?

    #if os(macOS)
    @State private var thumbnail: NSImage?
    #endif

    var body: some View {
        HStack(spacing: 10) {
            thumbnailView
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.created, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(isSelected ? accent : .secondary)
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(macOS)
        .task(id: entry.id) { await loadThumbnail() }
        #endif
    }

    @ViewBuilder
    private var thumbnailView: some View {
        #if os(macOS)
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 42, height: 42)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        #endif
    }

    /// Title is the first non-empty line of the body with image markdown
    /// stripped, so the row shows real text instead of `![file](path)`.
    private var title: String {
        let stripped = entry.body.replacingOccurrences(
            of: #"!\[[^\]]*\]\([^\)]*\)"#,
            with: "",
            options: .regularExpression
        )
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(no title)" }
        return trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
    }

    #if os(macOS)
    private func loadThumbnail() async {
        guard let root = journalRoot,
              let path = MarkdownImageRenderer.firstImagePath(in: entry.body) else {
            thumbnail = nil
            return
        }
        let url = root.appendingPathComponent(path)
        let image = await Task.detached(priority: .utility) {
            ThumbnailCache.shared.thumbnail(for: url)
        }.value
        thumbnail = image
    }
    #endif
}

#if os(macOS)
/// Loads small, memory-cached thumbnails efficiently (decodes a downscaled
/// image rather than the full-resolution original).
final class ThumbnailCache: @unchecked Sendable {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    func thumbnail(for url: URL, maxPixel: CGFloat = 96) -> NSImage? {
        let key = url.path as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceThumbnailMaxPixelSize: maxPixel,
                  kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary)
        else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }
}
#endif
