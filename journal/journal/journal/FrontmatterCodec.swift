import Foundation

enum FrontmatterCodec {
    static func encode(_ entry: JournalEntry) -> String {
        var lines: [String] = []
        lines.append("---")
        lines.append("id: \(entry.id)")
        lines.append("created: \(iso.string(from: entry.created))")
        lines.append("modified: \(iso.string(from: entry.modified))")
        lines.append("source: \(entry.source.rawValue)")
        if !entry.tags.isEmpty {
            lines.append("tags: [\(entry.tags.joined(separator: ", "))]")
        }
        if let originalPath = entry.originalPath {
            lines.append("original_path: \(originalPath)")
        }
        if let loc = entry.location {
            lines.append("location_lat: \(loc.latitude)")
            lines.append("location_lon: \(loc.longitude)")
            if let label = loc.label, !label.isEmpty {
                lines.append("location_label: \(label)")
            }
        }
        lines.append("---")
        lines.append("")
        lines.append(entry.body)
        return lines.joined(separator: "\n")
    }

    static func decode(_ text: String) -> JournalEntry? {
        var lines = text.components(separatedBy: "\n")
        guard let first = lines.first, first.trimmingCharacters(in: .whitespaces) == "---" else {
            return nil
        }
        lines.removeFirst()

        var meta: [String: String] = [:]
        var bodyStart: Int?
        for (idx, line) in lines.enumerated() {
            if line.trimmingCharacters(in: .whitespaces) == "---" {
                bodyStart = idx + 1
                break
            }
            if let colon = line.firstIndex(of: ":") {
                let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                meta[key] = value
            }
        }
        guard let start = bodyStart else { return nil }
        let bodyLines = Array(lines[start...]).drop(while: { $0.isEmpty })
        let body = bodyLines.joined(separator: "\n")

        guard
            let id = meta["id"],
            let createdStr = meta["created"], let created = iso.date(from: createdStr),
            let modifiedStr = meta["modified"], let modified = iso.date(from: modifiedStr)
        else {
            return nil
        }
        let source = JournalEntry.Source(rawValue: meta["source"] ?? "native") ?? .native
        let tags: [String]
        if let raw = meta["tags"] {
            tags = raw
                .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        } else {
            tags = []
        }

        let location: EntryLocation?
        if let latStr = meta["location_lat"], let lat = Double(latStr),
           let lonStr = meta["location_lon"], let lon = Double(lonStr) {
            location = EntryLocation(
                latitude: lat,
                longitude: lon,
                label: meta["location_label"]
            )
        } else {
            location = nil
        }

        return JournalEntry(
            id: id,
            created: created,
            modified: modified,
            source: source,
            body: body,
            tags: tags,
            originalPath: meta["original_path"],
            location: location
        )
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
