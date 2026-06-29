import SwiftUI

struct OnThisDayPanel: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let date: Date
    let excludeID: String
    let onSelect: (JournalEntry) -> Void
    let onDismiss: () -> Void

    private var matchingEntries: [JournalEntry] {
        let cal = Calendar.current
        let target = cal.dateComponents([.month, .day], from: date)
        return store.entries.filter { entry in
            guard entry.id != excludeID else { return false }
            let c = cal.dateComponents([.month, .day], from: entry.created)
            return c.month == target.month && c.day == target.day
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if matchingEntries.isEmpty {
                empty
            } else {
                list
            }
        }
        .frame(width: 280)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("On This Day")
                    .font(.headline)
                    .foregroundStyle(settings.accentColor)
                Text(date, format: .dateTime.month(.wide).day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.tertiary)
            Text("No matching days")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text("You haven't journaled on \(date, format: .dateTime.month(.wide).day()) in any previous year yet.\nFuture-you will find this one here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List {
            ForEach(matchingEntries) { entry in
                Button {
                    onSelect(entry)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.created, format: .dateTime.year().month(.abbreviated).day())
                            .font(.caption)
                            .foregroundStyle(settings.accentColor)
                        Text(preview(entry))
                            .font(.callout)
                            .lineLimit(3)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func preview(_ entry: JournalEntry) -> String {
        let trimmed = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "(empty)" }
        return trimmed
    }
}
