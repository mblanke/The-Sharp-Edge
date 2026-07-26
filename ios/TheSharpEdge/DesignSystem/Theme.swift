import SwiftUI

/// "C · Faïence" design tokens — ported from web/src/lib/tokens.css.
/// Blue-and-white kitchen tile with an ochre mustard accent.
/// Quantities are always mono; scale changes flash accent.
enum Theme {
    // Core tokens
    static let paper = Color(hex: 0xF2F3F5)       // background
    static let ink = Color(hex: 0x14161C)         // primary text
    static let faint = Color(hex: 0x5F6570)       // secondary text
    static let primary = Color(hex: 0x1F4A8F)     // accent / section rules
    static let primaryDeep = Color(hex: 0x14315F) // primary buttons, nav, quantities
    static let accent = Color(hex: 0x8A5E17)      // eyebrow, flash, focus ring
    static let line = Color(hex: 0xDCDEE3)        // borders / dashed rules
    static let card = Color(hex: 0xFBFCFD)        // card fill
    static let offWhite = Color(hex: 0xF7F8FA)    // text on primary

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
