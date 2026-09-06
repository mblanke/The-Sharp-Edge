import SwiftUI
import CoreText

/// Type system: Fraunces (display), Work Sans (body), Spline Sans Mono (quantities/labels).
///
/// Every font scales with Dynamic Type. A design size is mapped to the nearest built-in
/// text style: bundled faces use `Font.custom(_:size:relativeTo:)`, which keeps the exact
/// design size at the default setting and scales from there; the system fallbacks use
/// `Font.system(_:design:weight:)`, which is the only system path that scales. Before
/// this every font was `.system(size:)` — fixed — so the Larger Text setting a cook
/// relies on in the kitchen did nothing in this app.
enum Typography {
    /// Nearest text style for a design size. The default point sizes are: largeTitle 34,
    /// title 28, title2 22, title3 20, body 17, callout 16, subheadline 15, footnote 13,
    /// caption 12, caption2 11.
    static func textStyle(for size: CGFloat) -> Font.TextStyle {
        switch size {
        case 33...: return .largeTitle
        case 25..<33: return .title
        case 21..<25: return .title2
        case 18.5..<21: return .title3
        case 16.5..<18.5: return .body
        case 15.5..<16.5: return .callout
        case 14..<15.5: return .subheadline
        case 12.5..<14: return .footnote
        case 11.5..<12.5: return .caption
        default: return .caption2
        }
    }

    /// Returns a registered custom font by name, or nil if it isn't available.
    private static func custom(_ names: [String], size: CGFloat) -> Font? {
        for name in names where UIFont(name: name, size: size) != nil {
            return Font.custom(name, size: size, relativeTo: textStyle(for: size))
        }
        return nil
    }

    /// The bundled faces are static instances (one file per weight), so the weight
    /// picks the file: semibold and up take the heavier face.
    private static func heavy(_ weight: Font.Weight) -> Bool {
        [.semibold, .bold, .heavy, .black].contains(weight)
    }

    /// Display / headings — Fraunces at the design's 650 weight, else system serif.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        custom(["Fraunces-SemiBold", "Fraunces72pt-SemiBold", "Fraunces"], size: size)
            ?? .system(textStyle(for: size), design: .serif, weight: weight)
    }

    /// Body — Work Sans, else system default.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let faces = heavy(weight) ? ["WorkSans-SemiBold", "WorkSans-Regular"] : ["WorkSans-Regular", "WorkSans"]
        return custom(faces, size: size)
            ?? .system(textStyle(for: size), design: .default, weight: weight)
    }

    /// Quantities & labels — Spline Sans Mono, else system monospaced. The app's signature.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        let faces = heavy(weight)
            ? ["SplineSansMono-SemiBold", "SplineSansMono-Medium"]
            : ["SplineSansMono-Medium", "SplineSansMono-Regular", "SplineSansMono"]
        return custom(faces, size: size)
            ?? .system(textStyle(for: size), design: .monospaced, weight: weight)
    }
}

/// Registers any bundled .ttf/.otf fonts at launch so custom faces become available.
/// No-op when none are bundled — the system fallbacks in Typography keep everything working.
enum FontRegistrar {
    static func registerIfPresent() {
        guard let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) else { return }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        if let otf = Bundle.main.urls(forResourcesWithExtension: "otf", subdirectory: nil) {
            for url in otf { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
        }
    }
}
