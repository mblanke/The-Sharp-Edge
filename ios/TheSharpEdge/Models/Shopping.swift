import Foundation

/// Mirrors api/app/schemas/shopping.py.
///
/// Quantities are merged server-side: adding a second recipe adds to a line rather
/// than replacing it, and the arithmetic (unit families, kitchen fractions) is the
/// canonical implementation in services/shopping.py. The client only displays.

struct ShoppingItem: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var amount: Double
    var unit: String
    /// Already rendered by the server — kitchen fractions, "to taste" for amount 0.
    var display: String
    var toTaste: Bool
    var checked: Bool
    var recipes: [String]
    /// Routinely hides gluten; worth verifying the label in the shop.
    var checkGluten: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, amount, unit, display, checked, recipes
        case toTaste = "to_taste"
        case checkGluten = "check_gluten"
    }
}

struct ShoppingList: Codable {
    var items: [ShoppingItem] = []
}

struct ShoppingAdd: Encodable {
    var slug: String
    var targetYield: Int?

    enum CodingKeys: String, CodingKey {
        case slug
        case targetYield = "target_yield"
    }
}

struct ShoppingToggle: Encodable {
    var checked: Bool
}
