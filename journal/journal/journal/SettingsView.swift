import SwiftUI

#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Editor") {
                Picker("Font", selection: $settings.fontStyle) {
                    ForEach(EditorFontStyle.allCases) { style in
                        Text(style.rawValue)
                            .font(.system(size: 14, design: style.design))
                            .tag(style)
                    }
                }

                HStack {
                    Text("Size")
                    Slider(value: $settings.fontSize, in: 11...28, step: 1)
                    Text("\(Int(settings.fontSize)) pt")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 50, alignment: .trailing)
                }

                Text("The quick brown fox jumps over the lazy dog.")
                    .font(settings.editorFont)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(6)
            }

            Section("Appearance") {
                ColorPicker(
                    "Highlight color",
                    selection: Binding(
                        get: { settings.accentColor },
                        set: { settings.accentColor = $0 }
                    ),
                    supportsOpacity: false
                )

                HStack(spacing: 12) {
                    Button("Phoenix Amber") {
                        settings.accentRed = 0.93
                        settings.accentGreen = 0.66
                        settings.accentBlue = 0.40
                    }
                    Button("Cool Teal") {
                        settings.accentRed = 0.36
                        settings.accentGreen = 0.78
                        settings.accentBlue = 0.78
                    }
                    Button("Magenta") {
                        settings.accentRed = 0.85
                        settings.accentGreen = 0.40
                        settings.accentBlue = 0.78
                    }
                    Button("Sage") {
                        settings.accentRed = 0.55
                        settings.accentGreen = 0.74
                        settings.accentBlue = 0.55
                    }
                }
                .controlSize(.small)
            }

            Section("Journal Location") {
                HStack {
                    Text(store.journalRoot?.path ?? "Not set")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Change…", action: changeFolder)
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 520, minHeight: 420)
    }

    private func changeFolder() {
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
