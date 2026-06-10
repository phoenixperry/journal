import SwiftUI

struct SearchResultsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    let query: String
    let currentEntryID: String
    let onSelect: (JournalEntry) -> Void

    private var results: [JournalEntry] {
        let q = query.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return store.entries.filter { $0.body.lowercased().contains(q) }
    }

    var body: some View {
        Group {
            if results.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.tertiary)
                    Text("No matches")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section("\(results.count) result\(results.count == 1 ? "" : "s")") {
                        ForEach(results) { entry in
                            SearchResultRow(
                                entry: entry,
                                query: query,
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
                        }
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

private struct SearchResultRow: View {
    let entry: JournalEntry
    let query: String
    let isSelected: Bool
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(entry.created, format: .dateTime.year().month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(accent)
            Text(snippet)
                .font(.callout)
                .lineLimit(3)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var snippet: String {
        let body = entry.body
        let lower = body.lowercased()
        let q = query.lowercased()
        guard let range = lower.range(of: q) else {
            return String(body.prefix(150))
        }
        let beforeChars = body.distance(from: body.startIndex, to: range.lowerBound)
        let contextBefore = min(beforeChars, 40)
        let snippetStart = body.index(range.lowerBound, offsetBy: -contextBefore)
        let afterLen = body.distance(from: range.upperBound, to: body.endIndex)
        let snippetEnd = body.index(range.upperBound, offsetBy: min(afterLen, 150))
        var result = String(body[snippetStart..<snippetEnd])
            .replacingOccurrences(of: "\n", with: " ")
        if snippetStart > body.startIndex { result = "…" + result }
        if snippetEnd < body.endIndex { result += "…" }
        return result
    }
}
