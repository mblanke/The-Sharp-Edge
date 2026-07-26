import SwiftUI
import UIKit

/// "C · Faïence" design tokens — ported from web/src/lib/tokens.css.
/// Blue-and-white kitchen tile with an ochre mustard accent, in a light and a dark
/// scheme. Every token resolves against the system appearance, so the app follows
/// the iPad rather than fighting it — which also keeps SwiftUI's own controls
/// (Form, List, TextField) in step with our hand-painted surfaces. Before this,
/// an iPad in dark mode drew white system text on our hardcoded light fills.
///
/// Note the split between `primaryDeep` and `inkAccent`: `primaryDeep` is a *fill*
/// that carries `offWhite` text, `inkAccent` is the same blue used *as* text. They
/// are identical in light and necessarily diverge in dark.
///
/// Quantities are always mono; scale changes flash accent.
enum Theme {
    // Core tokens — (light, dark)
    static let paper = Color(light: 0xF2F3F5, dark: 0x101319)       // background
    static let ink = Color(light: 0x14161C, dark: 0xE6E9EE)         // primary text
    static let faint = Color(light: 0x5F6570, dark: 0x98A0AD)       // secondary text
    static let primary = Color(light: 0x1F4A8F, dark: 0x7BA6E2)     // section rules, labels
    static let primaryDeep = Color(light: 0x14315F, dark: 0x2F5F9E) // button / nav fills
    static let inkAccent = Color(light: 0x14315F, dark: 0x8FB6EE)   // that blue, as text
    static let accent = Color(light: 0x8A5E17, dark: 0xD9A441)      // eyebrow, flash, focus
    static let line = Color(light: 0xDCDEE3, dark: 0x2A2F39)        // borders / dashed rules
    static let card = Color(light: 0xFBFCFD, dark: 0x171B22)        // card fill
    static let offWhite = Color(light: 0xF7F8FA, dark: 0xF7F8FA)    // text on primaryDeep

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

    /// Resolves per appearance. Backed by UIColor so it re-resolves live when the
    /// system flips, rather than being baked in at view-init time.
    init(light: UInt32, dark: UInt32) {
        self.init(UIColor { traits in
            UIColor(rgb: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

private extension UIColor {
    convenience init(rgb: UInt32) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1.0
        )
    }
}
