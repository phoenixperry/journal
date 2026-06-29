import SwiftUI

#if os(macOS)
import AppKit

struct SpellCheckedTextEditor: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var titleColor: NSColor
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

        context.coordinator.lastSyncedText = text

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? JournalTextView else { return }
        guard let storage = textView.textStorage as? JournalTextStorage else { return }

        let newBody = bodyAttributes()
        let newTitle = titleAttributes()
        let attrsChanged =
            (storage.bodyAttributes[.font] as? NSFont) != font
            || (storage.titleAttributes[.foregroundColor] as? NSColor) != newTitle[.foregroundColor] as? NSColor

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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    private func bodyAttributes() -> [NSAttributedString.Key: Any] {
        [
            .font: font,
            .foregroundColor: NSColor.labelColor
        ]
    }

    private func titleAttributes() -> [NSAttributedString.Key: Any] {
        let titleSize = font.pointSize * 1.35
        let titleFont = NSFont(descriptor: font.fontDescriptor, size: titleSize) ?? font
        return [
            .font: titleFont,
            .foregroundColor: titleColor
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

final class JournalTextView: NSTextView {
    var onProcessDroppedFiles: (([URL]) -> NSAttributedString?)?
    var onDropWebURL: ((URL) -> String?)?

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
