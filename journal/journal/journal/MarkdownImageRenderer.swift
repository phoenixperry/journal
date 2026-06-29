import Foundation

#if os(macOS)
import AppKit

enum MarkdownImageRenderer {
    private static let imageRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#)
    }()

    static func toAttributed(
        markdown: String,
        journalRoot: URL?,
        baseAttributes: [NSAttributedString.Key: Any],
        maxImageWidth: CGFloat = 400
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = markdown as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = imageRegex.matches(in: markdown, range: fullRange)

        var cursor = 0
        for match in matches {
            if match.range.location > cursor {
                let r = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: ns.substring(with: r), attributes: baseAttributes))
            }

            let altRange = match.range(at: 1)
            let pathRange = match.range(at: 2)
            let alt = altRange.location != NSNotFound ? ns.substring(with: altRange) : ""
            let path = pathRange.location != NSNotFound ? ns.substring(with: pathRange) : ""

            let attachment = ImageAttachment()
            attachment.relativePath = path
            attachment.altText = alt

            if let image = loadImage(relativePath: path, journalRoot: journalRoot) {
                attachment.image = image
                attachment.bounds = boundingRect(for: image.size, maxWidth: maxImageWidth)
            } else if let fallback = NSImage(systemSymbolName: "photo", accessibilityDescription: alt) {
                attachment.image = fallback
                attachment.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
            }

            result.append(NSAttributedString(attachment: attachment))
            cursor = match.range.location + match.range.length
        }

        if cursor < ns.length {
            let r = NSRange(location: cursor, length: ns.length - cursor)
            result.append(NSAttributedString(string: ns.substring(with: r), attributes: baseAttributes))
        }

        return result
    }

    static func toMarkdown(_ attributed: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let attachment = value as? ImageAttachment {
                result.append("![\(attachment.altText)](\(attachment.relativePath))")
            } else if value is NSTextAttachment {
                // Unknown attachment kind — skip
            } else {
                let sub = attributed.attributedSubstring(from: range).string
                result.append(sub)
            }
        }
        return result
    }

    static func boundingRect(for imageSize: NSSize, maxWidth: CGFloat) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CGRect(x: 0, y: 0, width: 40, height: 40)
        }
        if imageSize.width <= maxWidth {
            return CGRect(origin: .zero, size: imageSize)
        }
        let scale = maxWidth / imageSize.width
        return CGRect(x: 0, y: 0, width: maxWidth, height: imageSize.height * scale)
    }

    private static func loadImage(relativePath: String, journalRoot: URL?) -> NSImage? {
        guard let root = journalRoot else { return nil }
        let url = root.appendingPathComponent(relativePath)
        return NSImage(contentsOf: url)
    }
}
#endif
