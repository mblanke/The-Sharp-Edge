import SwiftUI
import CoreText

/// Type system: Fraunces (display), Work Sans (body), Spline Sans Mono (quantities/labels).
/// Falls back to system faces so the app builds and runs with zero bundled fonts.
/// Drop the .ttf files into the source folder and they register automatically via FontRegistrar.
enum Typography {
    /// Returns a registered custom font by name, or nil if it isn't available.
    private static func custom(_ names: [String], size: CGFloat) -> Font? {
        for name in names {
            if UIFont(name: name, size: size) != nil {
                return Font.custom(name, size: size)
            }
        }
        return nil
    }

    /// Display / headings — Fraunces, else system serif.
    static func display(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        custom(["Fraunces-SemiBold", "Fraunces72pt-SemiBold", "Fraunces"], size: size)
            ?? .system(size: size, weight: weight, design: .serif)
    }

    /// Body — Work Sans, else system default.
    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        custom(["WorkSans-Regular", "WorkSans"], size: size)
            ?? .system(size: size, weight: weight)
    }

    /// Quantities & labels — Spline Sans Mono, else system monospaced. The app's signature.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        custom(["SplineSansMono-Medium", "SplineSansMono-Regular", "SplineSansMono"], size: size)
            ?? .system(size: size, weight: weight, design: .monospaced)
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
