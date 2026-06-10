import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct EntryEditorView: View {
    @Environment(JournalStore.self) private var store
    @Environment(AppSettings.self) private var settings
    @Binding var entry: JournalEntry

    @State private var hasStartedWriting = false
    @State private var saveTask: Task<Void, Never>?
    @State private var recoveryTask: Task<Void, Never>?
    @State private var lastSavedAt: Date?

    var body: some View {
        VStack(spacing: 0) {
            editorSurface
                .padding(12)
                .onChange(of: entry.body) { _, newValue in
                    handleEdit(newValue)
                }

            statusBar
        }
        .onAppear {
            hasStartedWriting = !entry.body.isEmpty
        }
        .onReceive(NotificationCenter.default.publisher(for: .journalSaveRequested)) { _ in
            saveNow()
        }
        #if os(macOS)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in
            saveNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            saveNow()
        }
        #endif
    }

    @ViewBuilder
    private var editorSurface: some View {
        #if os(macOS)
        SpellCheckedTextEditor(
            text: $entry.body,
            font: settings.editorNSFont,
            titleColor: settings.accentNSColor,
            journalRoot: store.journalRoot,
            onProcessDroppedFiles: handleFileDrop,
            onDropWebURL: handleWebURLDrop
        )
        #else
        TextEditor(text: $entry.body)
            .font(settings.editorFont)
            .scrollContentBackground(.hidden)
        #endif
    }

    #if os(macOS)
    private func handleFileDrop(_ urls: [URL]) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.editorNSFont,
            .foregroundColor: NSColor.labelColor
        ]
        var first = true
        for url in urls {
            do {
                let relative = try store.copyAttachment(from: url, for: entry)
                if !first {
                    result.append(NSAttributedString(string: "\n\n", attributes: baseAttrs))
                }
                first = false

                if isImageURL(url) {
                    let attachment = ImageAttachment()
                    attachment.relativePath = relative
                    attachment.altText = url.lastPathComponent
                    if let root = store.journalRoot {
                        let absURL = root.appendingPathComponent(relative)
                        if let image = NSImage(contentsOf: absURL) {
                            attachment.image = image
                            attachment.bounds = MarkdownImageRenderer.boundingRect(
                                for: image.size,
                                maxWidth: 400
                            )
                        }
                    }
                    if entry.location == nil, let exifLocation = LocationExtractor.extract(from: url) {
                        entry.location = exifLocation
                    }
                    result.append(NSAttributedString(attachment: attachment))
                } else {
                    let link = "[\(url.lastPathComponent)](\(relative))"
                    result.append(NSAttributedString(string: link, attributes: baseAttrs))
                }
            } catch {
                print("Attachment copy failed: \(error)")
            }
        }
        return result.length > 0 ? result : nil
    }

    private func handleWebURLDrop(_ url: URL) -> String? {
        let label = url.host ?? url.absoluteString
        return "[\(label)](\(url.absoluteString))"
    }

    private func isImageURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .image)
    }
    #endif

    private var statusBar: some View {
        HStack(spacing: 8) {
            Text(entry.created, format: .dateTime.weekday(.wide).month().day().year().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            if let loc = entry.location {
                HStack(spacing: 3) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(settings.accentColor)
                    Text(loc.label ?? coordinateLabel(loc))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text(wordCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let lastSavedAt {
                Text("· Saved \(lastSavedAt, format: .dateTime.hour().minute().second())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 6)
        .background(.bar)
    }

    private func coordinateLabel(_ loc: EntryLocation) -> String {
        String(format: "%.4f, %.4f", loc.latitude, loc.longitude)
    }

    private var wordCountLabel: String {
        let count = entry.body.split(whereSeparator: { $0.isWhitespace }).count
        return count == 1 ? "1 word" : "\(count) words"
    }

    private func handleEdit(_ newBody: String) {
        if !newBody.isEmpty {
            hasStartedWriting = true
            entry.modified = Date()
        }
        scheduleAutosave()
        scheduleRecoveryWrite()
    }

    private func scheduleAutosave() {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if Task.isCancelled { return }
            await MainActor.run { saveNow() }
        }
    }

    private func scheduleRecoveryWrite() {
        guard hasStartedWriting else { return }
        recoveryTask?.cancel()
        recoveryTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            await MainActor.run { store.writeRecovery(entry) }
        }
    }

    private func saveNow() {
        guard hasStartedWriting else { return }
        do {
            try store.save(entry)
            lastSavedAt = Date()
        } catch {
            print("Save failed: \(error)")
        }
    }
}
