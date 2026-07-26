import Foundation

/// Mirrors api/app/schemas/recipe.py. Unknown keys are ignored on decode;
/// nil optionals are omitted on encode to match the server's exclude_none behaviour.

struct Ingredient: Codable, Hashable, Identifiable {
    var amount: Double        // 0 = to taste → em dash, never scales
    var unit: String
    var name: String
    var note: String?
    var section: String?

    // Stable identity for SwiftUI lists (index-independent within a version).
    var id: String { "\(section ?? "")|\(name)|\(unit)|\(amount)" }

    init(amount: Double = 0, unit: String = "", name: String, note: String? = nil, section: String? = nil) {
        self.amount = amount
        self.unit = unit
        self.name = name
        self.note = note
        self.section = section
    }

    enum CodingKeys: String, CodingKey { case amount, unit, name, note, section }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        section = try c.decodeIfPresent(String.self, forKey: .section)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(amount, forKey: .amount)
        try c.encode(unit, forKey: .unit)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(section, forKey: .section)
    }
}

struct Step: Codable, Hashable, Identifiable {
    var text: String
    var timerSeconds: Int?

    var id: String { text }

    init(text: String, timerSeconds: Int? = nil) {
        self.text = text
        self.timerSeconds = timerSeconds
    }

    enum CodingKeys: String, CodingKey {
        case text
        case timerSeconds = "timer_seconds"
    }
}

struct RecipeCard: Codable, Hashable, Identifiable {
    var slug: String
    var title: String
    var category: String
    var meta: String?
    var baseYield: Int
    var yieldWord: String
    var gf: Bool
    var noscale: Bool
    var status: String

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, category, meta
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
        case gf, noscale, status
    }
}

struct VersionOut: Codable, Hashable, Identifiable {
    var id: UUID
    var version: Int
    var label: String?
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]
    var isCurrent: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, label, ingredients, steps, notes
        case isCurrent = "is_current"
        case createdAt = "created_at"
    }
}

struct VersionSummary: Codable, Hashable, Identifiable {
    var id: UUID
    var version: Int
    var label: String?
    var isCurrent: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, version, label
        case isCurrent = "is_current"
        case createdAt = "created_at"
    }
}

struct RecipeFull: Codable, Hashable, Identifiable {
    var slug: String
    var title: String
    var category: String
    var meta: String?
    var baseYield: Int
    var yieldWord: String
    var gf: Bool
    var noscale: Bool
    var status: String
    var source: String?
    var currentVersion: VersionOut

    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, title, category, meta
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
        case gf, noscale, status, source
        case currentVersion = "current_version"
    }
}

/// POST body — creates a recipe and its version 1.
/// Differs from RecipeUpdate in exactly one way that matters: the slug is
/// caller-supplied and permanent. QR codes are printed against it (CLAUDE.md §5),
/// so it is generated once via /parse/slug and confirmed before save.
struct RecipeCreate: Codable, Identifiable {
    /// Presentation identity only — `sheet(item:)` needs it. Never sent on the wire.
    var id: String { slug.isEmpty ? "new" : slug }

    var slug: String
    var title: String
    var category: String
    var meta: String?
    var baseYield: Int
    var yieldWord: String
    var gf: Bool
    var noscale: Bool
    var source: String?
    var status: String
    var label: String?
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]

    init(slug: String = "", title: String = "", category: String = Category.order[0],
         meta: String? = nil, baseYield: Int = 4, yieldWord: String = "servings",
         gf: Bool = false, noscale: Bool = false, source: String? = nil,
         status: String = "draft", label: String? = nil,
         ingredients: [Ingredient] = [], steps: [Step] = [], notes: [String] = []) {
        self.slug = slug
        self.title = title
        self.category = category
        self.meta = meta
        self.baseYield = baseYield
        self.yieldWord = yieldWord
        self.gf = gf
        self.noscale = noscale
        self.source = source
        self.status = status
        self.label = label
        self.ingredients = ingredients
        self.steps = steps
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case slug, title, category, meta
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
        case gf, noscale, source, status, label
        case ingredients, steps, notes
    }
}

/// PUT body — appends a new version. Slug never changes.
struct RecipeUpdate: Codable {
    var title: String?
    var category: String?
    var meta: String?
    var baseYield: Int?
    var yieldWord: String?
    var gf: Bool?
    var noscale: Bool?
    var source: String?
    var status: String?
    var label: String?
    var ingredients: [Ingredient]
    var steps: [Step]
    var notes: [String]

    enum CodingKeys: String, CodingKey {
        case title, category, meta
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
        case gf, noscale, source, status, label
        case ingredients, steps, notes
    }
}
