import SwiftUI

enum SidebarMode: String, CaseIterable, Identifiable {
    case list = "List"
    case calendar = "Calendar"
    var id: String { rawValue }
}

struct SidebarView: View {
    let currentEntryID: String
    let onSelect: (JournalEntry) -> Void
    let onNew: () -> Void
    let onDeleted: (JournalEntry) -> Void

    @State private var mode: SidebarMode = .list
    @State private var searchQuery: String = ""

    var body: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 10)
                .padding(.top, 10)
                .padding(.bottom, 4)

            if !trimmedQuery.isEmpty {
                SearchResultsView(
                    query: trimmedQuery,
                    currentEntryID: currentEntryID,
                    onSelect: onSelect
                )
            } else {
                Picker("Mode", selection: $mode) {
                    ForEach(SidebarMode.allCases) { m in
                        Text(m.rawValue).tag(m)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(8)

                Divider()

                switch mode {
                case .list:
                    EntryListView(
                        currentEntryID: currentEntryID,
                        onSelect: onSelect,
                        onNew: onNew,
                        onDeleted: onDeleted
                    )
                case .calendar:
                    CalendarSidebarView(onSelect: onSelect)
                }
            }
        }
        .navigationTitle("Journal")
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(.secondary)
            TextField("Search", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(.callout)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.12))
        )
    }
}
