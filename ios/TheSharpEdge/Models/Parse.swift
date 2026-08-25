import Foundation

/// Mirrors api/app/schemas/parse.py — the deterministic text→structure helpers
/// behind the add-recipe flow. No model is involved on either side.

/// The four languages the app can take dictation in. Speech recognition runs
/// on-device where the OS has a local model; `ro-RO` currently does not, which the
/// capture screen surfaces rather than hides.
enum CaptureLanguage: String, CaseIterable, Identifiable, Codable {
    case en, fr, de, ro

    var id: String { rawValue }

    /// BCP-47 identifier handed to SFSpeechRecognizer.
    var localeIdentifier: String {
        switch self {
        case .en: return "en-US"
        case .fr: return "fr-FR"
        case .de: return "de-DE"
        case .ro: return "ro-RO"
        }
    }

    /// Endonym — someone dictating in German looks for "Deutsch", not "German".
    var displayName: String {
        switch self {
        case .en: return "English"
        case .fr: return "Français"
        case .de: return "Deutsch"
        case .ro: return "Română"
        }
    }

    var flag: String {
        switch self {
        case .en: return "🇬🇧"
        case .fr: return "🇫🇷"
        case .de: return "🇩🇪"
        case .ro: return "🇷🇴"
        }
    }
}

struct ParseIngredientsRequest: Encodable {
    var lines: [String]
    var lang: String
}

struct ParseIngredientsResponse: Decodable {
    var ingredients: [Ingredient]
}

struct SlugRequest: Encodable {
    var title: String
}

struct SlugResponse: Decodable {
    var slug: String
    var available: Bool
    var valid: Bool
}

struct CategoryRequest: Encodable {
    var spoken: String
    var lang: String
}

struct CategoryResponse: Decodable {
    var category: String?
}
