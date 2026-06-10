import SwiftUI

#if os(macOS)
import AppKit
#endif

struct FolderPickerView: View {
    @Environment(JournalStore.self) private var store

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "folder.badge.plus")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)

            Text("Choose where to save your journal")
                .font(.title2)

            Text("Pick any folder — Proton Drive, iCloud, Dropbox, or just local.\nYour entries will be saved as markdown files.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Choose folder…", action: pickFolder)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .padding(.top, 8)
        }
        .padding(40)
    }

    private func pickFolder() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose a folder for your journal entries"
        if panel.runModal() == .OK, let url = panel.url {
            store.setJournalRoot(url)
        }
        #endif
    }
}
