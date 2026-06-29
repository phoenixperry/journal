import SwiftUI

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
                            accent: settings.accentColor
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(
                            entry.id == currentEntryID
                                ? settings.accentColor.opacity(0.25)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                        .onTapGesture { onSelect(entry) }
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.created, format: .dateTime.weekday(.abbreviated).month().day().hour().minute())
                .font(.caption)
                .foregroundStyle(isSelected ? accent : .secondary)
            Text(preview)
                .font(.callout)
                .lineLimit(2)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var preview: String {
        let trimmed = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        return trimmed.split(separator: "\n").first.map(String.init) ?? trimmed
    }
}
