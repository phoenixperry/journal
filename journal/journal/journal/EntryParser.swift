import Foundation

enum EntryParser {
    struct ParsedEntry: Identifiable {
        let id = UUID()
        let date: Date
        let body: String
        let imagePaths: [String]

        init(date: Date, body: String, imagePaths: [String] = []) {
            self.date = date
            self.body = body
            self.imagePaths = imagePaths
        }
    }

    static func parse(_ text: String) -> [ParsedEntry] {
        let lines = text.components(separatedBy: "\n")
        var entries: [ParsedEntry] = []
        var currentDate: Date?
        var currentBodyLines: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let date = parseDateLine(trimmed) {
                if let prev = currentDate {
                    entries.append(ParsedEntry(date: prev, body: finish(currentBodyLines)))
                }
                currentDate = date
                currentBodyLines = []
            } else if currentDate != nil {
                currentBodyLines.append(line)
            }
        }
        if let prev = currentDate {
            entries.append(ParsedEntry(date: prev, body: finish(currentBodyLines)))
        }
        return entries
    }

    private static func finish(_ lines: [String]) -> String {
        lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let formatters: [DateFormatter] = {
        let patterns = [
            "MMMM d, yyyy h:mm a",
            "MMMM d, yyyy h:mma",
            "MMM d, yyyy h:mm a",
            "MMM d, yyyy h:mma"
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = pattern
            return f
        }
    }()

    private static func parseDateLine(_ line: String) -> Date? {
        guard line.count <= 60 else { return nil }
        let normalized = line.replacingOccurrences(of: "\u{00A0}", with: " ")
        for f in formatters {
            if let d = f.date(from: normalized) { return d }
        }
        return nil
    }
}
