import Foundation

#if os(macOS)
import AppKit

class ImageAttachment: NSTextAttachment {
    var relativePath: String = ""
    var altText: String = ""
}

/// The entry's first image is shown as a scrolling banner at the top of the
/// editor. In the text flow it is represented by this compact link chip (rather
/// than a duplicate inline picture). It still serializes back to `![alt](path)`
/// markdown because it subclasses `ImageAttachment`.
final class BannerLinkAttachment: ImageAttachment {}

/// An audio/video reference, drawn as a native play-button "pill" in the text
/// (Apple SF Symbol + label, no filename or path). Serializes to `[label](path)`.
final class MediaAttachment: NSTextAttachment {
    var relativePath: String = ""
    var label: String = ""
    var isVideo: Bool = false
    var font: NSFont = .systemFont(ofSize: 14)

    /// Renders the pill for the given playback state and stores it as the
    /// attachment image.
    func renderPill(playing: Bool) {
        let symbolName: String
        if isVideo {
            symbolName = "video.fill"
        } else {
            symbolName = playing ? "pause.fill" : "play.fill"
        }
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: font.pointSize * 1.35, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.controlAccentColor]))
        let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: label)?
            .withSymbolConfiguration(symbolConfig)
        let symbolSize = symbol?.size ?? NSSize(width: 18, height: 18)

        let textAttrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
        let str = NSAttributedString(string: label, attributes: textAttrs)
        let textSize = str.size()

        let padX: CGFloat = 10, padY: CGFloat = 6, gap: CGFloat = 6
        let contentHeight = max(symbolSize.height, textSize.height)
        let size = NSSize(
            width: ceil(padX + symbolSize.width + gap + textSize.width + padX),
            height: ceil(contentHeight + padY * 2)
        )
        let image = NSImage(size: size)
        image.lockFocus()
        let pill = NSBezierPath(
            roundedRect: NSRect(origin: .zero, size: size),
            xRadius: size.height / 2,
            yRadius: size.height / 2
        )
        NSColor.secondaryLabelColor.withAlphaComponent(0.12).setFill()
        pill.fill()
        symbol?.draw(in: NSRect(
            x: padX,
            y: (size.height - symbolSize.height) / 2,
            width: symbolSize.width,
            height: symbolSize.height
        ))
        str.draw(at: NSPoint(
            x: padX + symbolSize.width + gap,
            y: (size.height - textSize.height) / 2
        ))
        image.unlockFocus()
        self.image = image
        self.bounds = CGRect(origin: .zero, size: size)
    }
}
#endif
