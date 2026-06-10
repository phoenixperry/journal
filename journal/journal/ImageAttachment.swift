import Foundation

#if os(macOS)
import AppKit

final class ImageAttachment: NSTextAttachment {
    var relativePath: String = ""
    var altText: String = ""
}
#endif
