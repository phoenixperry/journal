import Foundation

enum ImportError: LocalizedError {
    case unsupportedFormat(String)
    case textutilFailed(String)
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext): "Unsupported file format: .\(ext)"
        case .textutilFailed(let err): "Could not convert file: \(err)"
        case .notConfigured: "Journal folder is not set up yet."
        }
    }
}

enum Importer {
    static func extractText(from url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "txt", "md", "markdown":
            return try String(contentsOf: url, encoding: .utf8)
        case "docx", "doc", "rtf", "rtfd", "odt":
            return try runTextutil(url)
        default:
            throw ImportError.unsupportedFormat(ext)
        }
    }

    private static func runTextutil(_ url: URL) throws -> String {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        task.arguments = ["-convert", "txt", "-stdout", url.path]
        let outPipe = Pipe()
        let errPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = errPipe
        try task.run()
        task.waitUntilExit()
        if task.terminationStatus != 0 {
            let err = String(
                data: errPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "unknown error"
            throw ImportError.textutilFailed(err)
        }
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    @MainActor
    static func importEntries(
        _ parsed: [EntryParser.ParsedEntry],
        sourceURL: URL,
        into store: JournalStore
    ) throws -> Int {
        guard let root = store.journalRoot else {
            throw ImportError.notConfigured
        }

        let rawDir = root.appendingPathComponent("imports/raw", isDirectory: true)
        try FileManager.default.createDirectory(at: rawDir, withIntermediateDirectories: true)
        let destURL = uniqueDestination(in: rawDir, filename: sourceURL.lastPathComponent)
        try? FileManager.default.copyItem(at: sourceURL, to: destURL)
        let relativeOriginal = "imports/raw/\(destURL.lastPathComponent)"

        let ext = sourceURL.pathExtension.lowercased()
        let source: JournalEntry.Source
        switch ext {
        case "html", "htm": source = .importedHTML
        case "txt", "md", "markdown": source = .importedText
        default: source = .importedDocx
        }

        let sourceDir = sourceURL.deletingLastPathComponent()
        var idCounts: [String: Int] = [:]
        var imported = 0
        for p in parsed {
            let baseID = JournalEntry.idString(for: p.date)
            let count = (idCounts[baseID] ?? 0) + 1
            idCounts[baseID] = count
            let id = count > 1 ? "\(baseID)-\(count)" : baseID

            let scratchEntry = JournalEntry(
                id: id,
                created: p.date,
                modified: p.date,
                source: source,
                body: "",
                tags: [],
                originalPath: relativeOriginal,
                location: nil
            )

            var imageRefs: [String] = []
            for imgPath in p.imagePaths {
                let decoded = imgPath.removingPercentEncoding ?? imgPath
                let absURL = sourceDir.appendingPathComponent(decoded)
                guard FileManager.default.fileExists(atPath: absURL.path) else { continue }
                if let relative = try? store.copyAttachment(from: absURL, for: scratchEntry) {
                    imageRefs.append("![](\(relative))")
                }
            }

            let finalBody: String
            if imageRefs.isEmpty {
                finalBody = p.body
            } else {
                let imageBlock = imageRefs.joined(separator: "\n\n")
                finalBody = p.body.isEmpty
                    ? imageBlock
                    : "\(p.body)\n\n\(imageBlock)"
            }

            let entry = JournalEntry(
                id: id,
                created: p.date,
                modified: p.date,
                source: source,
                body: finalBody,
                tags: [],
                originalPath: relativeOriginal,
                location: nil
            )
            try store.save(entry)
            imported += 1
        }
        return imported
    }

    private static func uniqueDestination(in dir: URL, filename: String) -> URL {
        let fm = FileManager.default
        let initial = dir.appendingPathComponent(filename)
        if !fm.fileExists(atPath: initial.path) { return initial }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 2
        while true {
            let suffix = ext.isEmpty ? "\(stem)-\(n)" : "\(stem)-\(n).\(ext)"
            let candidate = dir.appendingPathComponent(suffix)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }
}
