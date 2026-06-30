import SwiftUI
import UniformTypeIdentifiers

#if os(macOS)
import AppKit
#endif

struct ParsedSource: Identifiable {
    let id = UUID()
    let url: URL
    let entries: [EntryParser.ParsedEntry]
}

struct ImportView: View {
    @Environment(JournalStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pickedURL: URL?
    @State private var pickedIsFolder = false
    @State private var batch: [ParsedSource] = []
    @State private var errorMessage: String?
    @State private var isImporting = false
    @State private var importedCount: Int?

    private static let supportedExtensions: Set<String> = [
        "docx", "doc", "rtf", "rtfd", "odt",
        "pdf",
        "txt", "md", "markdown",
        "html", "htm"
    ]

    private var totalEntries: Int {
        batch.reduce(0) { $0 + $1.entries.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 680, minHeight: 540)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import Journal")
                    .font(.title2)
                if let url = pickedURL {
                    Text(url.lastPathComponent)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
    }

    @ViewBuilder
    private var content: some View {
        if let importedCount {
            successView(count: importedCount)
        } else if let error = errorMessage {
            errorView(message: error)
        } else if pickedURL == nil {
            pickerView
        } else if totalEntries == 0 {
            emptyView
        } else {
            previewView
        }
    }

    private var pickerView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "doc.text.below.ecg")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(.secondary)
            Text("Import from a file or folder")
                .font(.title3)
            Text("File: pick one .docx, .pdf, .txt, .html, or similar.\nFolder: every supported file inside is imported.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 12) {
                Button("Choose File…") { pick(directories: false) }
                    .controlSize(.large)
                Button("Choose Folder…") { pick(directories: true) }
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text(message)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Start Over", action: reset)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Spacer()
            Text("No entries found.")
                .font(.headline)
            Text(emptyMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Start Over", action: reset)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyMessage: String {
        if pickedIsFolder {
            return "Walked the folder but found no supported files\nwith parseable entries."
        }
        return "No date headers found in this file.\nText/Word needs lines like \"November 17, 2018 8:40 AM\".\nHTML needs Apple Journal page headers."
    }

    private var previewView: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(totalEntries) entries found")
                        .font(.headline)
                    if pickedIsFolder {
                        Text("from \(batch.count) file\(batch.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button(isImporting ? "Importing…" : "Import All", action: importAll)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isImporting)
            }
            .padding()

            List {
                ForEach(batch) { source in
                    if pickedIsFolder {
                        Section(source.url.lastPathComponent) {
                            ForEach(source.entries) { entry in
                                entryRow(entry)
                            }
                        }
                    } else {
                        ForEach(source.entries) { entry in
                            entryRow(entry)
                        }
                    }
                }
            }
        }
    }

    private func entryRow(_ entry: EntryParser.ParsedEntry) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(entry.date, format: .dateTime.year().month(.wide).day().hour().minute())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(entry.body.isEmpty ? "(empty)" : String(entry.body.prefix(250)))
                .font(.callout)
                .lineLimit(4)
        }
        .padding(.vertical, 4)
    }

    private func successView(count: Int) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("Imported \(count) entries")
                .font(.title3)
            Text("They've been added to your journal with their original dates.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pick(directories: Bool) {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.canChooseFiles = !directories
        panel.canChooseDirectories = directories
        panel.allowsMultipleSelection = false

        if !directories {
            panel.allowedContentTypes = Self.supportedExtensions.compactMap {
                UTType(filenameExtension: $0)
            }
        }

        if panel.runModal() == .OK, let url = panel.url {
            pickedURL = url
            pickedIsFolder = directories
            parsePicked(url, isFolder: directories)
        }
        #endif
    }

    private func parsePicked(_ url: URL, isFolder: Bool) {
        do {
            if isFolder {
                batch = try parseFolder(url)
            } else {
                let entries = try parseSingleFile(url)
                batch = entries.isEmpty ? [] : [ParsedSource(url: url, entries: entries)]
            }
            errorMessage = nil
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func parseFolder(_ folder: URL) throws -> [ParsedSource] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var sources: [ParsedSource] = []
        for case let fileURL as URL in enumerator {
            let ext = fileURL.pathExtension.lowercased()
            guard Self.supportedExtensions.contains(ext) else { continue }
            do {
                let entries = try parseSingleFile(fileURL)
                if !entries.isEmpty {
                    sources.append(ParsedSource(url: fileURL, entries: entries))
                }
            } catch {
                // Skip files we can't parse; surface a summary later if needed
                continue
            }
        }
        return sources.sorted { $0.url.lastPathComponent < $1.url.lastPathComponent }
    }

    private func parseSingleFile(_ url: URL) throws -> [EntryParser.ParsedEntry] {
        let ext = url.pathExtension.lowercased()
        if ext == "html" || ext == "htm" {
            let html = try String(contentsOf: url, encoding: .utf8)
            return HTMLJournalParser.parse(html)
        } else {
            let text = try Importer.extractText(from: url)
            return EntryParser.parse(text)
        }
    }

    private func importAll() {
        isImporting = true
        do {
            var total = 0
            for source in batch {
                total += try Importer.importEntries(
                    source.entries,
                    sourceURL: source.url,
                    into: store
                )
            }
            isImporting = false
            importedCount = total
        } catch {
            isImporting = false
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
        }
    }

    private func reset() {
        pickedURL = nil
        pickedIsFolder = false
        batch = []
        errorMessage = nil
        importedCount = nil
    }
}
