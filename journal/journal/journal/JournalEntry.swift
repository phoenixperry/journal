import Foundation

struct EntryLocation: Hashable {
    var latitude: Double
    var longitude: Double
    var label: String?
}

struct JournalEntry: Identifiable, Hashable {
    let id: String
    var created: Date
    var modified: Date
    var source: Source
    var body: String
    var tags: [String]
    var originalPath: String?
    var location: EntryLocation?

    enum Source: String {
        case native
        case importedDocx = "imported-docx"
        case importedText = "imported-text"
        case importedHTML = "imported-html"
    }

    static func newDraft(now: Date = Date()) -> JournalEntry {
        JournalEntry(
            id: idString(for: now),
            created: now,
            modified: now,
            source: .native,
            body: "",
            tags: [],
            originalPath: nil,
            location: nil
        )
    }

    static func idString(for date: Date) -> String {
        idFormatter.string(from: date)
    }

    private static let idFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HHmmss"
        f.timeZone = .current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}
