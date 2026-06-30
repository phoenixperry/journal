import SwiftUI

#if os(macOS)
import AppKit
import AVFoundation

struct SpellCheckedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var titleColor: NSColor
    var lineHeight: CGFloat
    var headerImage: NSImage?
    var headerHeight: CGFloat
    var headerImageURL: URL?
    var journalRoot: URL?
    var onProcessDroppedFiles: (([URL]) -> NSAttributedString?)?
    var onDropWebURL: ((URL) -> String?)?

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let container = NSTextContainer()
        container.widthTracksTextView = true
        container.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(container)

        let textStorage = JournalTextStorage()
        textStorage.bodyAttributes = bodyAttributes()
        textStorage.titleAttributes = titleAttributes()
        textStorage.addLayoutManager(layoutManager)

        let textView = JournalTextView(frame: .zero, textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]

        textView.delegate = context.coordinator
        textView.drawsBackground = false
        textView.isRichText = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.textContainerInset = NSSize(width: 12, height: 16)

        textView.isContinuousSpellCheckingEnabled = true
        textView.isAutomaticSpellingCorrectionEnabled = true
        textView.isGrammarCheckingEnabled = true
        textView.isAutomaticTextReplacementEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = true
        textView.isAutomaticDashSubstitutionEnabled = true

        textView.registerForDraggedTypes([.fileURL, .URL, .string])
        textView.typingAttributes = bodyAttributes()

        let attributed = MarkdownImageRenderer.toAttributed(
            markdown: text,
            journalRoot: journalRoot,
            baseAttributes: bodyAttributes()
        )
        textStorage.setAttributedString(attributed)

        textView.onProcessDroppedFiles = { urls in onProcessDroppedFiles?(urls) }
        textView.onDropWebURL = { url in onDropWebURL?(url) }
        textView.headerImage = headerImage
        textView.headerHeight = headerHeight
        textView.headerImageURL = headerImageURL
        textView.journalRoot = journalRoot

        context.coordinator.lastSyncedText = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? JournalTextView else { return }
        guard let storage = textView.textStorage as? JournalTextStorage else { return }

        let newBody = bodyAttributes()
        let newTitle = titleAttributes()
        let oldLineHeight = (storage.bodyAttributes[.paragraphStyle] as? NSParagraphStyle)?.lineHeightMultiple
        let attrsChanged =
            (storage.bodyAttributes[.font] as? NSFont) != font
            || (storage.titleAttributes[.foregroundColor] as? NSColor) != newTitle[.foregroundColor] as? NSColor
            || oldLineHeight != lineHeight

        storage.bodyAttributes = newBody
        storage.titleAttributes = newTitle

        if text != context.coordinator.lastSyncedText {
            let attributed = MarkdownImageRenderer.toAttributed(
                markdown: text,
                journalRoot: journalRoot,
                baseAttributes: newBody
            )
            storage.setAttributedString(attributed)
            context.coordinator.lastSyncedText = text
        } else if attrsChanged {
            storage.refresh()
        }

        textView.typingAttributes = newBody
        textView.onProcessDroppedFiles = { urls in onProcessDroppedFiles?(urls) }
        textView.onDropWebURL = { url in onDropWebURL?(url) }
        textView.headerImage = headerImage
        textView.headerHeight = headerHeight
        textView.headerImageURL = headerImageURL
        textView.journalRoot = journalRoot
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func paragraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = lineHeight
        return style
    }

    private func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    private func titleAttributes() -> [NSAttributedString.Key: Any] {
        let titleSize = font.pointSize * 1.35
        let titleFont = NSFont(descriptor: font.fontDescriptor, size: titleSize) ?? font
        return [
            .font: titleFont,
            .foregroundColor: titleColor,
            .paragraphStyle: paragraphStyle()
        ]
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var lastSyncedText: String = ""

        init(text: Binding<String>) {
            self._text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            let md = MarkdownImageRenderer.toMarkdown(textView.attributedString())
            lastSyncedText = md
            text = md
        }
    }
}

final class JournalTextView: NSTextView, AVAudioPlayerDelegate {
    var onProcessDroppedFiles: (([URL]) -> NSAttributedString?)?
    var onDropWebURL: ((URL) -> String?)?
    /// Full-size file URL of the banner image, opened when the banner is clicked.
    var headerImageURL: URL?
    var journalRoot: URL?

    private var audioPlayer: AVAudioPlayer?
    private weak var playingMedia: MediaAttachment?

    // Clicking the banner opens the full image; clicking a media pill plays it.
    override func mouseDown(with event: NSEvent) {
        if headerHeight > 0, let url = headerImageURL {
            let point = convert(event.locationInWindow, from: nil)
            if point.y <= headerHeight + textContainerInset.height {
                NSWorkspace.shared.open(url)
                return
            }
        }
        if let media = mediaAttachment(at: event), let root = journalRoot {
            let url = root.appendingPathComponent(media.relativePath)
            if media.isVideo {
                NSWorkspace.shared.open(url) // video plays in QuickTime
            } else {
                toggleAudio(media, url: url)
            }
            return
        }
        super.mouseDown(with: event)
    }

    private func mediaAttachment(at event: NSEvent) -> MediaAttachment? {
        guard let layoutManager, let textContainer, let storage = textStorage, storage.length > 0 else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        var fraction: CGFloat = 0
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer, fractionOfDistanceThroughGlyph: &fraction)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard charIndex < storage.length else { return nil }
        return storage.attribute(.attachment, at: charIndex, effectiveRange: nil) as? MediaAttachment
    }

    private func toggleAudio(_ media: MediaAttachment, url: URL) {
        // Tapping the currently-playing pill pauses/resumes it.
        if playingMedia === media, let player = audioPlayer {
            if player.isPlaying { player.pause(); media.renderPill(playing: false) }
            else { player.play(); media.renderPill(playing: true) }
            needsDisplay = true
            return
        }
        playingMedia?.renderPill(playing: false)
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.play()
            audioPlayer = player
            playingMedia = media
            media.renderPill(playing: true)
            needsDisplay = true
        } catch {
            print("Audio playback failed: \(error)")
        }
    }

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        playingMedia?.renderPill(playing: false)
        playingMedia = nil
        audioPlayer = nil
        needsDisplay = true
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        // Pointing-hand cursor over the clickable banner.
        if headerHeight > 0, headerImageURL != nil {
            addCursorRect(
                NSRect(x: 0, y: 0, width: bounds.width, height: headerHeight + textContainerInset.height),
                cursor: .pointingHand
            )
        }
    }

    /// The entry's first image, drawn as a blog-style banner across the top of
    /// the document. It lives in the scrolling content (not pinned), so it
    /// scrolls away normally as you read down the page.
    var headerImage: NSImage? {
        didSet {
            guard headerImage !== oldValue else { return }
            needsDisplay = true
        }
    }
    var headerHeight: CGFloat = 0 {
        didSet {
            guard headerHeight != oldValue else { return }
            applyBannerExclusion()
            needsDisplay = true
        }
    }

    /// Reserve the banner's space with a full-width exclusion rect at the top of
    /// the text container. This lets NSTextView own all the geometry — sizing,
    /// cursor placement, hit-testing, scrolling — while we just paint the image
    /// into the reserved gap. Far more robust than overriding the view's frame.
    private func applyBannerExclusion() {
        guard let container = textContainer else { return }
        if headerHeight > 0 {
            container.exclusionPaths = [
                NSBezierPath(rect: NSRect(x: 0, y: 0, width: 100_000, height: headerHeight))
            ]
        } else {
            container.exclusionPaths = []
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawHeaderBanner()
    }

    private func drawHeaderBanner() {
        guard headerHeight > 0, let image = headerImage,
              image.size.width > 0, image.size.height > 0 else { return }

        // Fill from the very top of the document down to where the text now
        // begins (reserved height + the container's top inset), edge to edge.
        let bannerHeight = headerHeight + textContainerInset.height
        let rect = NSRect(x: 0, y: 0, width: bounds.width, height: bannerHeight)
        guard let context = NSGraphicsContext.current else { return }
        context.saveGraphicsState()
        NSBezierPath(rect: rect).addClip()

        // Aspect-fill the banner area.
        let scale = max(rect.width / image.size.width, rect.height / image.size.height)
        let drawSize = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2,
            y: rect.midY - drawSize.height / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
        context.restoreGraphicsState()
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDraggableURLs(sender) ? .copy : super.draggingEntered(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        hasDraggableURLs(sender) ? .copy : super.draggingUpdated(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let pb = sender.draggingPasteboard
        let allURLs = (pb.readObjects(forClasses: [NSURL.self]) as? [URL]) ?? []
        let fileURLs = allURLs.filter { $0.isFileURL }
        let webURLs = allURLs.filter { !$0.isFileURL }

        let combined = NSMutableAttributedString()
        var hasContent = false

        if !fileURLs.isEmpty, let fragment = onProcessDroppedFiles?(fileURLs), fragment.length > 0 {
            combined.append(fragment)
            hasContent = true
        }

        for web in webURLs {
            if let md = onDropWebURL?(web), !md.isEmpty {
                if hasContent {
                    combined.append(NSAttributedString(string: "\n\n", attributes: typingAttributes))
                }
                combined.append(NSAttributedString(string: md, attributes: typingAttributes))
                hasContent = true
            }
        }

        guard hasContent else {
            return super.performDragOperation(sender)
        }

        let point = convert(sender.draggingLocation, from: nil)
        let charIndex = characterIndexForInsertion(at: point)
        let range = NSRange(location: charIndex, length: 0)

        guard shouldChangeText(in: range, replacementString: combined.string) else { return false }
        textStorage?.replaceCharacters(in: range, with: combined)
        didChangeText()
        setSelectedRange(NSRange(location: charIndex + combined.length, length: 0))
        return true
    }

    private func hasDraggableURLs(_ sender: NSDraggingInfo) -> Bool {
        sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
    }
}
#endif
