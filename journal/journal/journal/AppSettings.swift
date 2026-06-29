import SwiftUI
import Observation

#if os(macOS)
import AppKit
#endif

enum EditorFontStyle: String, CaseIterable, Identifiable {
    case system = "System"
    case serif = "Serif"
    case monospaced = "Monospaced"
    case rounded = "Rounded"

    var id: String { rawValue }

    var design: Font.Design {
        switch self {
        case .system: .default
        case .serif: .serif
        case .monospaced: .monospaced
        case .rounded: .rounded
        }
    }
}

@Observable
@MainActor
final class AppSettings {
    var fontStyle: EditorFontStyle {
        didSet { UserDefaults.standard.set(fontStyle.rawValue, forKey: Self.fontStyleKey) }
    }
    var fontSize: Double {
        didSet { UserDefaults.standard.set(fontSize, forKey: Self.fontSizeKey) }
    }
    var accentRed: Double {
        didSet { UserDefaults.standard.set(accentRed, forKey: Self.accentRedKey) }
    }
    var accentGreen: Double {
        didSet { UserDefaults.standard.set(accentGreen, forKey: Self.accentGreenKey) }
    }
    var accentBlue: Double {
        didSet { UserDefaults.standard.set(accentBlue, forKey: Self.accentBlueKey) }
    }

    private static let fontStyleKey = "EditorFontStyle"
    private static let fontSizeKey = "EditorFontSize"
    private static let accentRedKey = "AccentColorRed"
    private static let accentGreenKey = "AccentColorGreen"
    private static let accentBlueKey = "AccentColorBlue"

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.fontStyleKey) ?? EditorFontStyle.serif.rawValue
        self.fontStyle = EditorFontStyle(rawValue: raw) ?? .serif
        let size = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        self.fontSize = size > 0 ? size : 16

        let defaults = UserDefaults.standard
        self.accentRed = (defaults.object(forKey: Self.accentRedKey) as? Double) ?? 0.93
        self.accentGreen = (defaults.object(forKey: Self.accentGreenKey) as? Double) ?? 0.66
        self.accentBlue = (defaults.object(forKey: Self.accentBlueKey) as? Double) ?? 0.40
    }

    var editorFont: Font {
        .system(size: fontSize, design: fontStyle.design)
    }

    var accentColor: Color {
        get { Color(red: accentRed, green: accentGreen, blue: accentBlue) }
        set {
            #if os(macOS)
            if let ns = NSColor(newValue).usingColorSpace(.sRGB) {
                accentRed = Double(ns.redComponent)
                accentGreen = Double(ns.greenComponent)
                accentBlue = Double(ns.blueComponent)
            }
            #endif
        }
    }

    #if os(macOS)
    var editorNSFont: NSFont {
        switch fontStyle {
        case .system:
            return NSFont.systemFont(ofSize: fontSize)
        case .serif:
            let base = NSFont.systemFont(ofSize: fontSize)
            if let descriptor = base.fontDescriptor.withDesign(.serif),
               let font = NSFont(descriptor: descriptor, size: fontSize) {
                return font
            }
            return base
        case .monospaced:
            return NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        case .rounded:
            let base = NSFont.systemFont(ofSize: fontSize)
            if let descriptor = base.fontDescriptor.withDesign(.rounded),
               let font = NSFont(descriptor: descriptor, size: fontSize) {
                return font
            }
            return base
        }
    }

    var accentNSColor: NSColor {
        NSColor(red: accentRed, green: accentGreen, blue: accentBlue, alpha: 1.0)
    }
    #endif
}
