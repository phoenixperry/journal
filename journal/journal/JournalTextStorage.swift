import Foundation

#if os(macOS)
import AppKit

final class JournalTextStorage: NSTextStorage {
    private let backing = NSMutableAttributedString()
    var bodyAttributes: [NSAttributedString.Key: Any] = [:]
    var titleAttributes: [NSAttributedString.Key: Any] = [:]
    var titleMaxLength: Int = 120

    override var string: String { backing.string }

    override func attributes(
        at location: Int,
        effectiveRange range: NSRangePointer?
    ) -> [NSAttributedString.Key: Any] {
        backing.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backing.replaceCharacters(in: range, with: str)
        let delta = (str as NSString).length - range.length
        edited(.editedCharacters, range: range, changeInLength: delta)
        endEditing()
    }

    override func setAttributes(
        _ attrs: [NSAttributedString.Key: Any]?,
        range: NSRange
    ) {
        beginEditing()
        backing.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    override func processEditing() {
        applyTitleStyling()
        super.processEditing()
    }

    private func applyTitleStyling() {
        let s = backing.string as NSString
        let length = s.length
        guard length > 0 else { return }

        let firstNewline = s.range(of: "\n")
        let titleEnd: Int
        if firstNewline.location == NSNotFound {
            titleEnd = length
        } else {
            titleEnd = firstNewline.location
        }

        let useTitleStyle = titleEnd > 0 && titleEnd <= titleMaxLength

        let fullRange = NSRange(location: 0, length: length)
        backing.enumerateAttribute(.attachment, in: fullRange, options: []) { value, range, _ in
            guard value == nil else { return }
            let rangeEnd = range.location + range.length

            if !useTitleStyle {
                backing.setAttributes(bodyAttributes, range: range)
                return
            }

            if rangeEnd <= titleEnd {
                backing.setAttributes(titleAttributes, range: range)
            } else if range.location >= titleEnd {
                backing.setAttributes(bodyAttributes, range: range)
            } else {
                let titleR = NSRange(
                    location: range.location,
                    length: titleEnd - range.location
                )
                let bodyR = NSRange(
                    location: titleEnd,
                    length: rangeEnd - titleEnd
                )
                backing.setAttributes(titleAttributes, range: titleR)
                backing.setAttributes(bodyAttributes, range: bodyR)
            }
        }
    }

    func refresh() {
        beginEditing()
        edited(
            .editedAttributes,
            range: NSRange(location: 0, length: backing.length),
            changeInLength: 0
        )
        endEditing()
    }
}
#endif
