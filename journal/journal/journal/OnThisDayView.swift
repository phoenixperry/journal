import SwiftUI

struct OnThisDayView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let date: Date
    let onSelect: (JournalEntry) -> Void

    private var matchingEntries: [JournalEntry] {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: date)
        return store.entries.filter { entry in
            let ec = cal.dateComponents([.month, .day], from: entry.created)
            return ec.month == comps.month && ec.day == comps.day
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("On This Day")
                        .font(.title2)
                    Text(date, format: .dateTime.month(.wide).day())
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
            Divider()

            if matchingEntries.isEmpty {
                VStack {
                    Spacer()
                    Text("No entries for this day yet.")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(matchingEntries) { entry in
                        Button {
                            onSelect(entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.created, format: .dateTime.year().month(.wide).day().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(preview(entry))
                                    .font(.body)
                                    .lineLimit(4)
                                    .multilineTextAlignment(.leading)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
    }

    private func preview(_ entry: JournalEntry) -> String {
        let trimmed = entry.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(empty)" : trimmed
    }
}
