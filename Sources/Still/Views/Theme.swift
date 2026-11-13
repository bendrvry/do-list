import AppKit
import SwiftUI

/// The Quiet Utility palette, type scale and spacing. One place to tune the look.
enum Theme {
    // MARK: Colour

    static let background = Color(nsColor: .still.background)
    static let primaryText = Color(nsColor: .still.primaryText)
    static let secondaryText = Color(nsColor: .still.secondaryText)
    static let placeholder = Color(nsColor: .still.placeholder)
    static let divider = Color(nsColor: .still.divider)
    static let hover = Color(nsColor: .still.hover)
    static let completedText = Color(nsColor: .still.completedText)
    static let checkboxStroke = Color(nsColor: .still.checkboxStroke)
    static let checkboxStrokeHover = Color(nsColor: .still.checkboxStrokeHover)
    static let checkboxFill = Color(nsColor: .still.checkboxFill)
    static let checkmark = Color(nsColor: .still.checkmark)
    /// The hairline around the menu bar dropdown.
    static let panelEdge = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(white: 1, alpha: 0.14)
            : NSColor(white: 0, alpha: 0.12)
    })

    // MARK: Type

    static let headingFont = Font.system(size: 22, weight: .semibold)
    static let dateFont = Font.system(size: 13)
    static let taskFont = Font.system(size: 14)
    nonisolated(unsafe) static let taskNSFont = NSFont.systemFont(ofSize: 14)
    static let smallFont = Font.system(size: 12)

    // MARK: Spacing

    /// Distance from the window edge to the checkbox / heading.
    static let margin: CGFloat = 22
    /// Hover backgrounds extend this far beyond the text column on each side.
    static let rowBleed: CGFloat = 8
    static let rowVerticalPadding: CGFloat = 10
    static let checkboxSize: CGFloat = 18
    static let checkboxGap: CGFloat = 12
    static let rowCornerRadius: CGFloat = 7
    /// Height of the first line of task text; the checkbox is centred on it.
    static let lineHeight: CGFloat = ceil(taskNSFont.ascender - taskNSFont.descender + taskNSFont.leading)

    // MARK: Motion

    static func animation(_ reduceMotion: Bool, duration: Double = 0.2) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: duration)
    }
}

extension NSColor {
    enum still {
        static let background = dynamic(light: 0xFAFAF9, dark: 0x1C1C1E)
        static let primaryText = dynamic(light: 0x202124, dark: 0xF3F3F3)
        // Slightly darker than #85868A so 13pt secondary text meets 4.5:1.
        static let secondaryText = dynamic(light: 0x76777B, dark: 0x98989D, lightHC: 0x56575B, darkHC: 0xB8B8BD)
        static let placeholder = dynamic(light: 0xA2A3A6, dark: 0x6F6F74, lightHC: 0x76777B, darkHC: 0x98989D)
        static let divider = dynamic(light: 0xEAEAE8, dark: 0x313134, lightHC: 0xC4C4C2, darkHC: 0x55555A)
        static let hover = dynamic(light: 0xF1F1EF, dark: 0x262629)
        static let completedText = dynamic(light: 0xA0A1A3, dark: 0x76767B, lightHC: 0x6E6F72, darkHC: 0xA0A0A5)
        static let checkboxStroke = dynamic(light: 0xC2C3C5, dark: 0x5A5A5F, lightHC: 0x8A8B8E, darkHC: 0x8A8A8F)
        static let checkboxStrokeHover = dynamic(light: 0x8E8F93, dark: 0x8E8E93)
        static let checkboxFill = dynamic(light: 0xA9AAAD, dark: 0x6C6C71, lightHC: 0x6E6F72, darkHC: 0xA0A0A5)
        static let checkmark = dynamic(light: 0xFFFFFF, dark: 0x1C1C1E)

        private static func dynamic(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) -> NSColor {
            NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [
                    .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
                ])
                switch match {
                case .darkAqua: return NSColor(hex: dark)
                case .accessibilityHighContrastDarkAqua: return NSColor(hex: darkHC ?? dark)
                case .accessibilityHighContrastAqua: return NSColor(hex: lightHC ?? light)
                default: return NSColor(hex: light)
                }
            }
        }
    }

    convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
