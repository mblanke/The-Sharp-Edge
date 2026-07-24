import SwiftUI

/// "Washi & bottle green" design tokens — ported from web/src/lib/tokens.css.
/// Quantities are always mono; scale changes flash copper.
enum Theme {
    // Core tokens
    static let paper = Color(hex: 0xF2F1EC)     // background
    static let ink = Color(hex: 0x20241E)       // primary text
    static let faint = Color(hex: 0x6B6F63)     // secondary text
    static let green = Color(hex: 0x3E6B4A)     // accent / section rules
    static let greenDeep = Color(hex: 0x2C4F36) // primary buttons, nav, quantities
    static let copper = Color(hex: 0xC87A2E)    // eyebrow, flash, focus ring
    static let line = Color(hex: 0xD9D7CC)      // borders / dashed rules
    static let card = Color(hex: 0xFAFAF6)      // card fill
    static let offWhite = Color(hex: 0xF4F3EC)  // text on green

    // Radii
    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 20
        static let pill: CGFloat = 999
    }

    // Spacing
    enum Space {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 36
    }

    static let minTouch: CGFloat = 44
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
