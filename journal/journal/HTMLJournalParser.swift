import Foundation

enum HTMLJournalParser {
    static func parse(_ html: String) -> [EntryParser.ParsedEntry] {
        extractPageContainers(from: html).compactMap(parseContainer)
    }

    private static func extractPageContainers(from html: String) -> [String] {
        let pattern = #"<div\s+class=['"]pageContainer['"][^>]*>(.*?)(?=<div\s+class=['"]pageContainer['"]|</body>)"#
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..., in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[r])
        }
    }

    private static func parseContainer(_ block: String) -> EntryParser.ParsedEntry? {
        guard let date = extractDate(from: block) else { return nil }
        let title = extractText(in: block, divClass: "title")
            .map(decodeEntities)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let rawBody = extractText(in: block, divClass: "bodyText") ?? block
        let bodyMarkdown = htmlToMarkdown(rawBody)

        let finalBody: String
        if let title, !title.isEmpty {
            finalBody = "\(title)\n\n\(bodyMarkdown)"
        } else {
            finalBody = bodyMarkdown
        }
        let images = extractImageSources(from: block)
        return EntryParser.ParsedEntry(date: date, body: finalBody, imagePaths: images)
    }

    private static let imgWithSrcRegex: NSRegularExpression = {
        try! NSRegularExpression(
            pattern: #"<img[^>]*src=['"]([^'"]+)['"][^>]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        )
    }()

    private static func extractImageSources(from block: String) -> [String] {
        let ns = block as NSString
        let range = NSRange(location: 0, length: ns.length)
        return imgWithSrcRegex.matches(in: block, range: range).compactMap { match in
            guard match.numberOfRanges > 1,
                  let r = Range(match.range(at: 1), in: block) else { return nil }
            let src = String(block[r])
            if src.hasPrefix("data:") || src.hasPrefix("http://") || src.hasPrefix("https://") {
                return nil
            }
            return src
        }
    }

    private static func extractDate(from block: String) -> Date? {
        guard let raw = extractText(in: block, divClass: "pageHeader") else { return nil }
        let trimmed = decodeEntities(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in dateFormatters {
            if let date = formatter.date(from: trimmed) {
                return noonOf(date)
            }
        }
        return nil
    }

    private static func noonOf(_ date: Date) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: date)
        comps.hour = 12
        comps.minute = 0
        return Calendar.current.date(from: comps) ?? date
    }

    private static func extractText(in block: String, divClass: String) -> String? {
        let pattern = "<div\\s+class=['\"]\(divClass)['\"][^>]*>(.*?)</div>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.dotMatchesLineSeparators, .caseInsensitive]
        ) else { return nil }
        let range = NSRange(block.startIndex..., in: block)
        guard let match = regex.firstMatch(in: block, range: range),
              let r = Range(match.range(at: 1), in: block) else { return nil }
        return String(block[r])
    }

    private static let dateFormatters: [DateFormatter] = {
        let patterns = [
            "EEEE, d MMMM yyyy",
            "EEEE, MMMM d, yyyy",
            "EEEE, d MMM yyyy",
            "d MMMM yyyy",
            "MMMM d, yyyy"
        ]
        return patterns.map { p in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = .current
            f.dateFormat = p
            return f
        }
    }()

    private static func htmlToMarkdown(_ html: String) -> String {
        var s = html

        s = replaceMatches(in: s, pattern: #"<ul[^>]*>"#, with: "")
        s = s.replacingOccurrences(of: "</ul>", with: "\n", options: .caseInsensitive)
        s = replaceMatches(in: s, pattern: #"<ol[^>]*>"#, with: "")
        s = s.replacingOccurrences(of: "</ol>", with: "\n", options: .caseInsensitive)
        s = replaceMatches(in: s, pattern: #"<li[^>]*>"#, with: "- ")
        s = s.replacingOccurrences(of: "</li>", with: "\n", options: .caseInsensitive)

        s = replaceMatches(in: s, pattern: #"<blockquote[^>]*>"#, with: "\n> ")
        s = s.replacingOccurrences(of: "</blockquote>", with: "\n", options: .caseInsensitive)

        s = replaceMatches(in: s, pattern: #"<p[^>]*>"#, with: "")
        s = s.replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)

        s = replaceMatches(in: s, pattern: #"<br\s*/?>"#, with: "\n")

        s = replaceMatches(in: s, pattern: #"<(strong|b)[^>]*>"#, with: "**")
        s = replaceMatches(in: s, pattern: #"</(strong|b)>"#, with: "**")
        s = replaceMatches(in: s, pattern: #"<(em|i)[^>]*>"#, with: "*")
        s = replaceMatches(in: s, pattern: #"</(em|i)>"#, with: "*")

        s = replaceMatches(in: s, pattern: #"<[^>]+>"#, with: "")

        s = decodeEntities(s)

        s = replaceMatches(in: s, pattern: #"\n{3,}"#, with: "\n\n")
        s = replaceMatches(in: s, pattern: #"[ \t]+\n"#, with: "\n")

        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replaceMatches(in s: String, pattern: String, with replacement: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return s }
        let range = NSRange(s.startIndex..., in: s)
        return regex.stringByReplacingMatches(in: s, range: range, withTemplate: replacement)
    }

    private static func decodeEntities(_ s: String) -> String {
        var t = s
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&hellip;", "…"),
            ("&ndash;", "–"),
            ("&mdash;", "—"),
            ("&lsquo;", "\u{2018}"),
            ("&rsquo;", "\u{2019}"),
            ("&ldquo;", "\u{201C}"),
            ("&rdquo;", "\u{201D}")
        ]
        for (entity, char) in named {
            t = t.replacingOccurrences(of: entity, with: char)
        }
        return decodeNumericEntities(t)
    }

    private static func decodeNumericEntities(_ s: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: #"&#(\d+);"#) else { return s }
        var result = s
        let range = NSRange(result.startIndex..., in: result)
        let matches = regex.matches(in: result, range: range).reversed()
        for match in matches {
            guard match.numberOfRanges > 1,
                  let numRange = Range(match.range(at: 1), in: result),
                  let codepoint = UInt32(result[numRange]),
                  let scalar = Unicode.Scalar(codepoint),
                  let fullRange = Range(match.range, in: result) else { continue }
            result.replaceSubrange(fullRange, with: String(Character(scalar)))
        }
        return result
    }
}
