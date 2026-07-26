import Foundation

/// Category ordering + allowed units.
///
/// Two naming schemes exist in the project: the long headers in `recipes-data.js`
/// ("Sauces, Dressings & Salsas", DECISIONS.md 2026-07-23) and the short print/glue-in
/// names the seed manifest actually writes to the DB ("Sauces & Salsas"). Everything
/// stored is short — `web/src/lib/types.ts` CATEGORY_ORDER and every seeded row — so
/// the short list is canonical here too, and the long headers are kept as aliases so
/// grouping stays stable either way. Anything the editor offers must be a name the
/// rest of the stack recognises.
enum Category {
    /// Canonical order — matches CATEGORY_ORDER in web/src/lib/types.ts and the seeded rows.
    static let order: [String] = [
        "Sauces & Salsas",
        "Marinades",
        "Salads",
        "Soups & Stews",
        "Sandwiches",
        "Pasta",
        "Entrées",
        "Sides",
        "Breakfast",
        "Baking & Desserts",
        "Drinks",
        "Appetizers & Preserves",
        "Reference",
    ]

    /// Long recipes-data.js headers mapped onto the canonical rank.
    private static let aliasRank: [String: Int] = [
        "Sauces, Dressings & Salsas": 0,
        "Marinades & Rubs": 1,
        "Tacos & Sandwiches": 4,
        "Pasta & Noodles": 5,
        "Side Dishes": 7,
    ]

    static func rank(_ category: String) -> Int {
        if let i = order.firstIndex(of: category) { return i }
        if let r = aliasRank[category] { return r }
        return order.count
    }

    /// Loose match for a dictated category name, used offline. The live path calls
    /// `/parse/category`, which knows the French/German/Romanian vocabulary too.
    static func match(_ spoken: String) -> String? {
        let probe = spoken
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        guard !probe.isEmpty else { return nil }
        return order.first {
            let name = $0.folding(options: [.diacriticInsensitive, .caseInsensitive],
                                  locale: Locale(identifier: "en_US"))
            return name == probe || name.contains(probe)
        }
    }
}

/// Units the API accepts (empty = countable; the counting noun lives in the name).
enum Units {
    static let allowed: [String] = ["", "g", "ml", "cup", "tbsp", "tsp", "lb", "oz"]

    /// A readable label for the unit picker.
    static func label(_ unit: String) -> String {
        unit.isEmpty ? "count" : unit
    }
}
