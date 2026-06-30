import Foundation

#if os(macOS)
import AppKit

enum MarkdownImageRenderer {
    private static let imageRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"!\[([^\]]*)\]\(([^\)]+)\)"#)
    }()

    /// Relative path of the first image in the markdown, if any. This image is
    /// rendered as the entry's banner header.
    static func firstImagePath(in markdown: String) -> String? {
        let ns = markdown as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        guard let match = imageRegex.firstMatch(in: markdown, range: fullRange) else { return nil }
        let pathRange = match.range(at: 2)
        return pathRange.location != NSNotFound ? ns.substring(with: pathRange) : nil
    }

    // Matches both `![alt](path)` images and `[label](path)` links; group 1 is
    // the optional leading "!" that distinguishes them.
    private static let linkRegex: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(!?)\[([^\]]*)\]\(([^\)]+)\)"#)
    }()

    private static let audioExtensions: Set<String> = ["m4a", "mp3", "wav", "aif", "aiff", "caf", "aac", "flac", "m4b"]
    private static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]

    static func isMediaPath(_ path: String) -> Bool {
        let ext = (path as NSString).pathExtension.lowercased()
        return audioExtensions.contains(ext) || videoExtensions.contains(ext)
    }

    static func isVideoPath(_ path: String) -> Bool {
        videoExtensions.contains((path as NSString).pathExtension.lowercased())
    }

    static func toAttributed(
        markdown: String,
        journalRoot: URL?,
        baseAttributes: [NSAttributedString.Key: Any],
        maxImageWidth: CGFloat = 400
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let ns = markdown as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = linkRegex.matches(in: markdown, range: fullRange)
        let baseFont = (baseAttributes[.font] as? NSFont) ?? .systemFont(ofSize: 14)

        var cursor = 0
        var imageIndex = 0
        for match in matches {
            if match.range.location > cursor {
                let r = NSRange(location: cursor, length: match.range.location - cursor)
                result.append(NSAttributedString(string: ns.substring(with: r), attributes: baseAttributes))
            }
            cursor = match.range.location + match.range.length

            let bang = ns.substring(with: match.range(at: 1))
            let labelRange = match.range(at: 2)
            let pathRange = match.range(at: 3)
            let label = labelRange.location != NSNotFound ? ns.substring(with: labelRange) : ""
            let path = pathRange.location != NSNotFound ? ns.substring(with: pathRange) : ""

            if bang == "!" {
                // The first image becomes the banner header (invisible placeholder
                // in the text); later images render inline.
                if imageIndex == 0 {
                    result.append(NSAttributedString(attachment: bannerPlaceholder(path: path, alt: label)))
                } else {
                    let attachment = ImageAttachment()
                    attachment.relativePath = path
                    attachment.altText = label
                    if let image = loadImage(relativePath: path, journalRoot: journalRoot) {
                        attachment.image = image
                        attachment.bounds = boundingRect(for: image.size, maxWidth: maxImageWidth)
                    } else if let fallback = NSImage(systemSymbolName: "photo", accessibilityDescription: label) {
                        attachment.image = fallback
                        attachment.bounds = CGRect(x: 0, y: 0, width: 40, height: 40)
                    }
                    result.append(NSAttributedString(attachment: attachment))
                }
                imageIndex += 1
            } else if isMediaPath(path) {
                // Audio/video → native play-button pill (no filename shown).
                let media = MediaAttachment()
                media.relativePath = path
                media.isVideo = isVideoPath(path)
                media.label = label.isEmpty ? (media.isVideo ? "Video" : "Audio") : label
                media.font = baseFont
                media.renderPill(playing: false)
                result.append(NSAttributedString(attachment: media))
            } else {
                // A regular link — leave the markdown as visible text.
                result.append(NSAttributedString(string: ns.substring(with: match.range), attributes: baseAttributes))
            }
        }

        if cursor < ns.length {
            let r = NSRange(location: cursor, length: ns.length - cursor)
            result.append(NSAttributedString(string: ns.substring(with: r), attributes: baseAttributes))
        }

        return result
    }

    /// An invisible stand-in for the entry's first image. The image itself is
    /// shown as the banner header (and opens full-size when clicked); in the
    /// text it occupies no space but still serializes back to `![alt](path)`.
    static func bannerPlaceholder(path: String, alt: String) -> BannerLinkAttachment {
        let attachment = BannerLinkAttachment()
        attachment.relativePath = path
        attachment.altText = alt
        attachment.image = NSImage(size: NSSize(width: 1, height: 1)) // avoids a broken-image glyph
        attachment.bounds = .zero
        return attachment
    }

    static func toMarkdown(_ attributed: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributed.length)
        attributed.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            if let media = value as? MediaAttachment {
                result.append("[\(media.label)](\(media.relativePath))")
            } else if let attachment = value as? ImageAttachment {
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
