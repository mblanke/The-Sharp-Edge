import Foundation

/// Category ordering + allowed units.
///
/// The seeded DB categories follow recipes-master.md headers (DECISIONS.md 2026-07-23),
/// i.e. the full CATS names from recipes-data.js. We rank by that canonical order and
/// keep the web print-order names as aliases so grouping is stable either way.
enum Category {
    /// Canonical category order — matches CATS in recipes-data.js (the seed source).
    static let order: [String] = [
        "Sauces, Dressings & Salsas",
        "Marinades & Rubs",
        "Salads",
        "Soups & Stews",
        "Tacos & Sandwiches",
        "Pasta & Noodles",
        "Entrées",
        "Side Dishes",
        "Breakfast",
        "Baking & Desserts",
        "Drinks",
        "Appetizers & Preserves",
        "Reference",
    ]

    /// Fallback aliases (web print/glue-in names) mapped to a canonical rank.
    private static let aliasRank: [String: Int] = [
        "Sauces & Salsas": 0,
        "Marinades": 1,
        "Sandwiches": 4,
        "Pasta": 5,
        "Sides": 7,
    ]

    static func rank(_ category: String) -> Int {
        if let i = order.firstIndex(of: category) { return i }
        if let r = aliasRank[category] { return r }
        return order.count
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
