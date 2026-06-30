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
                // The same date+time repeated at the top of the next page means
                // one entry runs across multiple pages — skip the repeated
                // header and keep appending instead of splitting the entry.
                if let prev = currentDate, date == prev {
                    continue
                }
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
        // Time-bearing patterns are listed first so a header that includes a
        // time (e.g. "Monday, December 15, 2025  7:51 AM") keeps its time
        // instead of matching a date-only pattern.
        let patterns = [
            "EEEE, MMMM d, yyyy h:mm a",
            "EEEE, MMMM d, yyyy h:mma",
            "MMMM d, yyyy h:mm a",
            "MMMM d, yyyy h:mma",
            "MMM d, yyyy h:mm a",
            "MMM d, yyyy h:mma",
            "EEEE, MMMM d, yyyy",
            "MMMM d, yyyy",
            "MMM d, yyyy"
        ]
        return patterns.map { pattern in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = pattern
            f.isLenient = false
            return f
        }
    }()

    private static let dateDetector: NSDataDetector? = {
        try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    }()

    private static func parseDateLine(_ line: String) -> Date? {
        // Collapse runs of whitespace (PDFs separate the date and time with a
        // wide gap) and drop non-breaking spaces before matching.
        let normalized = line.replacingOccurrences(of: "\u{00A0}", with: " ")
        let collapsed = normalized
            .split(whereSeparator: { $0 == " " || $0 == "\t" })
            .joined(separator: " ")
        guard !collapsed.isEmpty, collapsed.count <= 80 else { return nil }

        for f in formatters {
            if let d = f.date(from: collapsed) { return d }
        }
        return detectHeaderDate(in: collapsed)
    }

    /// Fallback for date headers the explicit formatters miss. Accepts a match
    /// only when it begins the line and covers most of it — so a date mentioned
    /// mid-sentence in the body isn't mistaken for an entry header.
    private static func detectHeaderDate(in line: String) -> Date? {
        guard let detector = dateDetector else { return nil }
        let ns = line as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = detector.firstMatch(in: line, options: [], range: range),
              let date = match.date else { return nil }
        guard match.range.location <= 2 else { return nil }
        let coverage = Double(match.range.length) / Double(max(ns.length, 1))
        guard coverage >= 0.5 else { return nil }
        return date
    }
}
