import SwiftUI

@main
struct journalApp: App {
    @State private var store = JournalStore()
    @State private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(settings)
                .tint(settings.accentColor)
                .preferredColorScheme(.dark)
        }
        .commands {
            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    NotificationCenter.default.post(name: .journalSaveRequested, object: nil)
                }
                .keyboardShortcut("s", modifiers: .command)
            }
            CommandGroup(after: .newItem) {
                Button("New Entry") {
                    NotificationCenter.default.post(name: .journalNewEntryRequested, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Import…") {
                    NotificationCenter.default.post(name: .journalImportRequested, object: nil)
                }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Toggle Journal Sidebar") {
                    NotificationCenter.default.post(name: .journalToggleSidebar, object: nil)
                }
                .keyboardShortcut("\\", modifiers: .command)
            }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .environment(store)
                .environment(settings)
        }
        #endif
    }
}

extension Notification.Name {
    static let journalSaveRequested = Notification.Name("journalSaveRequested")
    static let journalNewEntryRequested = Notification.Name("journalNewEntryRequested")
    static let journalImportRequested = Notification.Name("journalImportRequested")
    static let journalToggleSidebar = Notification.Name("journalToggleSidebar")
}
