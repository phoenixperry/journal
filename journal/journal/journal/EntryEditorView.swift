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

    @State private var showDateEditor = false

    #if os(macOS)
    @State private var headerImage: NSImage?
    @State private var headerImagePath: String?
    @State private var recorder = AudioRecorder()
    @State private var mediaStatus: String?
    #endif

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                editorSurface(availableHeight: geo.size.height)
                    .padding(12)
                    .onChange(of: entry.body) { _, newValue in
                        handleEdit(newValue)
                    }
            }

            statusBar
        }
        .onAppear {
            hasStartedWriting = !entry.body.isEmpty
            updateHeaderImage()
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
    private func editorSurface(availableHeight: CGFloat) -> some View {
        #if os(macOS)
        SpellCheckedTextEditor(
            text: $entry.body,
            font: settings.editorNSFont,
            titleColor: settings.accentNSColor,
            lineHeight: settings.lineHeight,
            headerImage: headerImage,
            headerHeight: headerImage != nil ? availableHeight * 0.30 : 0,
            headerImageURL: headerImageURL,
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
    private var headerImageURL: URL? {
        guard let path = headerImagePath, let root = store.journalRoot else { return nil }
        return root.appendingPathComponent(path)
    }
    #endif

    /// Reloads the banner image only when the entry's first image actually
    /// changes, so typing doesn't re-read the file on every keystroke.
    private func updateHeaderImage() {
        #if os(macOS)
        let path = MarkdownImageRenderer.firstImagePath(in: entry.body)
        guard path != headerImagePath else { return }
        headerImagePath = path
        if let path, let root = store.journalRoot {
            let img = NSImage(contentsOf: root.appendingPathComponent(path))
            print("[Banner] firstImagePath=\(path) loaded=\(img != nil) size=\(img?.size ?? .zero)")
            headerImage = img
        } else {
            print("[Banner] no header: path=\(String(describing: path)) root=\(store.journalRoot != nil)")
            headerImage = nil
        }
        #endif
    }

    private func applyDateChange(_ newDate: Date) {
        showDateEditor = false
        guard !entry.body.isEmpty else {
            // New, unsaved draft: just adjust the date in memory.
            entry.created = newDate
            entry.modified = Date()
            return
        }
        entry = store.reschedule(entry, to: newDate)
    }

    #if os(macOS)
    private func handleFileDrop(_ urls: [URL]) -> NSAttributedString? {
        let result = NSMutableAttributedString()
        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: settings.editorNSFont,
            .foregroundColor: NSColor.labelColor
        ]
        // If the entry has no image yet, the first dropped image becomes the
        // banner — insert it as a link chip directly so it isn't shown twice.
        var willBeFirstImage = MarkdownImageRenderer.firstImagePath(in: entry.body) == nil
        var first = true
        for url in urls {
            do {
                let isMedia = isAudioVisualURL(url)
                let relative = try store.copyAttachment(
                    from: url, for: entry,
                    subfolder: isMedia ? "media" : "images"
                )
                if !first {
                    result.append(NSAttributedString(string: "\n\n", attributes: baseAttrs))
                }
                first = false

                if isMedia {
                    let label = isVideoURL(url) ? "Video" : "Audio"
                    result.append(NSAttributedString(string: "[\(label)](\(relative))", attributes: baseAttrs))
                    if let mediaURL = store.journalRoot?.appendingPathComponent(relative) {
                        Task { await transcribeAndAppend(mediaURL) }
                    }
                } else if isImageURL(url) {
                    if entry.location == nil, let exifLocation = LocationExtractor.extract(from: url) {
                        entry.location = exifLocation
                    }
                    if willBeFirstImage {
                        willBeFirstImage = false
                        let placeholder = MarkdownImageRenderer.bannerPlaceholder(
                            path: relative,
                            alt: url.lastPathComponent
                        )
                        result.append(NSAttributedString(attachment: placeholder))
                        continue
                    }
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

    private func isAudioVisualURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .audio) || type.conforms(to: .movie) || type.conforms(to: .audiovisualContent)
    }

    private func isVideoURL(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension.lowercased()) else {
            return false
        }
        return type.conforms(to: .movie) || type.conforms(to: .video)
    }

    // MARK: - Audio recording & transcription

    @MainActor
    private func toggleRecording() async {
        if recorder.isRecording {
            mediaStatus = nil
            guard let tempURL = recorder.stop() else { return }
            await saveRecording(tempURL)
        } else {
            guard await recorder.requestPermission() else {
                mediaStatus = "Microphone access denied"
                return
            }
            if !recorder.start() {
                mediaStatus = "Couldn't start recording"
            }
        }
    }

    private func saveRecording(_ tempURL: URL) async {
        hasStartedWriting = true
        var addition = ""
        if let relative = try? store.copyAttachment(from: tempURL, for: entry, subfolder: "media") {
            addition += "\n\n[Audio recording](\(relative))"
        }
        mediaStatus = "Transcribing…"
        let transcript = (try? await MediaTranscriber.transcribe(url: tempURL)) ?? ""
        mediaStatus = nil
        if !transcript.isEmpty { addition += "\n\n\(transcript)" }
        if !addition.isEmpty {
            entry.body += addition
            entry.modified = Date()
            saveNow()
        }
        try? FileManager.default.removeItem(at: tempURL)
    }

    /// Transcribes a dropped audio/video file and appends the text to the entry.
    private func transcribeAndAppend(_ mediaURL: URL) async {
        mediaStatus = "Transcribing…"
        let transcript = (try? await MediaTranscriber.transcribe(url: mediaURL)) ?? ""
        mediaStatus = nil
        guard !transcript.isEmpty else { return }
        entry.body += "\n\n\(transcript)"
        entry.modified = Date()
        saveNow()
    }

    private func timeString(_ t: TimeInterval) -> String {
        String(format: "%d:%02d", Int(t) / 60, Int(t) % 60)
    }

    @ViewBuilder
    private var recordingControl: some View {
        if recorder.isRecording {
            Text(timeString(recorder.elapsed))
                .font(.caption).monospacedDigit().foregroundStyle(.red)
        } else if let mediaStatus {
            Text(mediaStatus)
                .font(.caption).foregroundStyle(.secondary)
        }
        Button {
            Task { await toggleRecording() }
        } label: {
            Image(systemName: recorder.isRecording ? "stop.circle.fill" : "mic.circle")
                .foregroundStyle(recorder.isRecording ? .red : .secondary)
        }
        .buttonStyle(.plain)
        .help(recorder.isRecording ? "Stop recording" : "Record a spoken or sound entry")
    }
    #endif

    private var statusBar: some View {
        HStack(spacing: 8) {
            Button {
                showDateEditor = true
            } label: {
                HStack(spacing: 4) {
                    Text(entry.created, format: .dateTime.weekday(.wide).month().day().year().hour().minute())
                    Image(systemName: "pencil")
                        .font(.system(size: 9))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Change this entry's date")
            .popover(isPresented: $showDateEditor, arrowEdge: .bottom) {
                DateEditorPopover(date: entry.created) { newDate in
                    applyDateChange(newDate)
                }
            }
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
            #if os(macOS)
            recordingControl
            #endif
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
        updateHeaderImage()
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

private struct DateEditorPopover: View {
    let onSave: (Date) -> Void
    @State private var draft: Date
    @Environment(\.dismiss) private var dismiss

    init(date: Date, onSave: @escaping (Date) -> Void) {
        self.onSave = onSave
        _draft = State(initialValue: date)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Entry date & time")
                .font(.headline)
            Text("Useful for entries imported from paper or old files, or to correct a wrong import date.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DatePicker("", selection: $draft, displayedComponents: [.date, .hourAndMinute])
                .datePickerStyle(.graphical)
                .labelsHidden()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
