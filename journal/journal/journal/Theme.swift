import SwiftUI

#if os(macOS)
import AppKit
#endif

extension Color {
    static let journalAccent = Color(red: 0.93, green: 0.66, blue: 0.40)
    static let journalAccentDim = Color(red: 0.93, green: 0.66, blue: 0.40).opacity(0.7)
}

#if os(macOS)
extension NSColor {
    static let journalAccent = NSColor(red: 0.93, green: 0.66, blue: 0.40, alpha: 1.0)
}
#endif
