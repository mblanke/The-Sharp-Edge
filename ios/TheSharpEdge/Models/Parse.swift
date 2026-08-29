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

/// Mirrors api/app/services/photo_import.py RecipeDraft — what the local vision
/// model reads off a photographed page. Review-first, like dictation: the draft
/// seeds the editor and nothing saves until the cook says so.
struct PhotoDraft: Decodable {
    var title: String
    var meta: String?
    var baseYield: Int
    var yieldWord: String
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case title, meta, ingredients, steps, notes
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
    }

    func toRecipeCreate(slug: String) -> RecipeCreate {
        RecipeCreate(slug: slug, title: title, category: Category.order[0],
                     meta: meta, baseYield: baseYield, yieldWord: yieldWord,
                     ingredients: ingredients, steps: steps, notes: notes)
    }
}

/// One hidden-gluten hit the server found in a drafted recipe. Mirrors
/// api/app/services/gf_audit.scan_ingredients. Celiac safety is load-bearing
/// (CLAUDE.md §1), so a warning the server computed is never dropped on the floor.
struct GFRisk: Decodable, Hashable, Identifiable {
    var ingredient: String
    var term: String
    var why: String

    var id: String { "\(ingredient)|\(term)" }
}

/// A library passage on its way into the notebook — the read loop closing.
/// Mirrors POST /recipes/parse-passage. Review-first like photo import: the draft
/// seeds the editor and nothing saves until the cook says so. The draft arrives
/// marked private, because corpus content stays inside this deployment (§1).
struct PassageDraftRequest: Encodable {
    var text: String
    var sourceTitle: String?
    var page: Int?

    enum CodingKeys: String, CodingKey {
        case text
        case sourceTitle = "source_title"
        case page
    }
}

struct PassageDraft: Decodable {
    var draft: PhotoDraft          // same shape: our parser produced both
    var source: String?
    var isPrivate: Bool
    var gfRisks: [GFRisk]?

    enum CodingKeys: String, CodingKey {
        case draft, source
        case isPrivate = "private"
        case gfRisks = "gf_risks"
    }

    /// Seed the editor, carrying the book · page as the source line and the tier flag.
    func toRecipeCreate(slug: String) -> RecipeCreate {
        var create = draft.toRecipeCreate(slug: slug)
        create.source = source
        create.isPrivate = isPrivate
        return create
    }
}

/// Mirrors api/app/services/translate.py — a recipe's words in another language.
/// Only strings travel; amounts, units and timers are carried through untouched
/// by the server, so a translation can never change a quantity.
struct TranslateRequest: Encodable {
    var target: String
    var title: String
    var meta: String?
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]
}

struct TranslateResponse: Decodable {
    var title: String
    var meta: String?
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]
}

/// A saved translation of one recipe version — the reading lens, not an edit.
struct RecipeTranslation: Decodable {
    var available: Bool
    var title: String?
    var meta: String?
    var ingredients: [Ingredient]?
    var steps: [Step]?
    var notes: [String]?
}
