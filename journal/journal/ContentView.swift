import SwiftUI

struct RootView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @State private var currentEntry: JournalEntry = .newDraft()
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .automatic
    @State private var showImport = false
    @State private var showOnThisDay = true
    @State private var showLocationPopover = false
    @State private var showInsights = false
    @State private var pendingRecovery: JournalEntry?
    @State private var didCheckRecovery = false

    var body: some View {
        Group {
            if store.isConfigured {
                NavigationSplitView(columnVisibility: $sidebarVisibility) {
                    SidebarView(
                        currentEntryID: currentEntry.id,
                        onSelect: { selected in
                            saveCurrentIfNeeded()
                            currentEntry = selected
                        },
                        onNew: startNewEntry,
                        onDeleted: handleDeleted
                    )
                    .navigationSplitViewColumnWidth(min: 260, ideal: 290, max: 420)
                } detail: {
                    detailArea
                }
                .onReceive(NotificationCenter.default.publisher(for: .journalNewEntryRequested)) { _ in
                    startNewEntry()
                }
                .onReceive(NotificationCenter.default.publisher(for: .journalImportRequested)) { _ in
                    showImport = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .journalToggleSidebar)) { _ in
                    toggleSidebar()
                }
                .sheet(isPresented: $showImport) {
                    ImportView()
                }
                .sheet(isPresented: $showInsights) {
                    InsightsView()
                }
                .onAppear(perform: checkPendingRecoveries)
                .alert(
                    "Restore unsaved entry?",
                    isPresented: recoveryAlertBinding,
                    presenting: pendingRecovery
                ) { entry in
                    Button("Restore") {
                        currentEntry = entry
                        store.clearRecovery(for: entry)
                        pendingRecovery = nil
                    }
                    Button("Discard", role: .destructive) {
                        store.clearRecovery(for: entry)
                        pendingRecovery = nil
                    }
                } message: { entry in
                    Text("Last edited \(entry.modified.formatted(date: .abbreviated, time: .standard)). The app may have quit before saving.")
                }
                .toolbar {
                    ToolbarItemGroup {
                        Button {
                            showOnThisDay.toggle()
                        } label: {
                            Image(systemName: "clock.arrow.circlepath")
                                .foregroundStyle(clockIconColor)
                        }
                        .help(onThisDayHelpText)

                        Button {
                            showInsights = true
                        } label: {
                            Image(systemName: "chart.bar.fill")
                                .foregroundStyle(.secondary)
                        }
                        .help("Insights")

                        Button {
                            showLocationPopover = true
                        } label: {
                            Image(systemName: currentEntry.location != nil ? "mappin.circle.fill" : "mappin.circle")
                                .foregroundStyle(currentEntry.location != nil ? settings.accentColor : .secondary)
                        }
                        .help(currentEntry.location.map { "Location: \($0.label ?? "set")" } ?? "Add location")
                        .popover(isPresented: $showLocationPopover) {
                            LocationEditorPopover(location: $currentEntry.location)
                        }

                        Button {
                            startNewEntry()
                        } label: {
                            Image(systemName: "square.and.pencil")
                        }
                        .help("New Entry (⌘N)")
                    }
                }
            } else {
                FolderPickerView()
            }
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var detailArea: some View {
        HStack(spacing: 0) {
            EntryEditorView(entry: $currentEntry)
                .id(currentEntry.id)
            if showOnThisDay {
                Divider()
                OnThisDayPanel(
                    date: currentEntry.created,
                    excludeID: currentEntry.id,
                    onSelect: { selected in
                        saveCurrentIfNeeded()
                        currentEntry = selected
                    },
                    onDismiss: { showOnThisDay = false }
                )
            }
        }
    }

    private var clockIconColor: Color {
        guard hasPastYearMatches else { return .secondary }
        return showOnThisDay ? settings.accentColor : .secondary
    }

    private var onThisDayHelpText: String {
        if !hasPastYearMatches {
            return "On This Day — no past entries on this date yet"
        }
        return showOnThisDay ? "Hide On This Day" : "Show On This Day"
    }

    private var hasPastYearMatches: Bool {
        let cal = Calendar.current
        let target = cal.dateComponents([.month, .day], from: currentEntry.created)
        return store.entries.contains { entry in
            guard entry.id != currentEntry.id else { return false }
            let c = cal.dateComponents([.month, .day], from: entry.created)
            return c.month == target.month && c.day == target.day
        }
    }

    private func saveCurrentIfNeeded() {
        guard !currentEntry.body.isEmpty else { return }
        try? store.save(currentEntry)
    }

    private func startNewEntry() {
        saveCurrentIfNeeded()
        currentEntry = .newDraft()
    }

    private func handleDeleted(_ deleted: JournalEntry) {
        if deleted.id == currentEntry.id {
            currentEntry = .newDraft()
        }
    }

    private var recoveryAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRecovery != nil },
            set: { if !$0 { pendingRecovery = nil } }
        )
    }

    private func checkPendingRecoveries() {
        guard !didCheckRecovery else { return }
        didCheckRecovery = true
        let pending = store.pendingRecoveries()
        pendingRecovery = pending.first
    }

    private func toggleSidebar() {
        switch sidebarVisibility {
        case .detailOnly:
            sidebarVisibility = .all
        default:
            sidebarVisibility = .detailOnly
        }
    }
}
