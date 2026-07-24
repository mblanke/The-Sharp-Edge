import Foundation

/// Mirrors the /recipes/{slug}/scale contract (api/app/schemas/recipe.py).
struct ScaleRequest: Codable {
    var targetYield: Int
    enum CodingKeys: String, CodingKey { case targetYield = "target_yield" }
}

struct ScaledIngredient: Codable, Hashable, Identifiable {
    var amount: Double
    var unit: String
    var name: String
    var note: String?
    var section: String?
    var scaledAmount: Double
    var display: String

    var id: String { "\(section ?? "")|\(name)|\(unit)" }

    enum CodingKeys: String, CodingKey {
        case amount, unit, name, note, section
        case scaledAmount = "scaled_amount"
        case display
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        amount = try c.decodeIfPresent(Double.self, forKey: .amount) ?? 0
        unit = try c.decodeIfPresent(String.self, forKey: .unit) ?? ""
        name = try c.decode(String.self, forKey: .name)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        section = try c.decodeIfPresent(String.self, forKey: .section)
        scaledAmount = try c.decodeIfPresent(Double.self, forKey: .scaledAmount) ?? 0
        display = try c.decodeIfPresent(String.self, forKey: .display) ?? ""
    }
}

struct ScaleResponse: Codable {
    var slug: String
    var baseYield: Int
    var targetYield: Int
    var yieldWord: String
    var ingredients: [ScaledIngredient]

    enum CodingKeys: String, CodingKey {
        case slug
        case baseYield = "base_yield"
        case targetYield = "target_yield"
        case yieldWord = "yield_word"
        case ingredients
    }
}
