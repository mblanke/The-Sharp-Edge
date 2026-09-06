import Foundation

/// One slot in the week: a recipe on a day at a meal, at the servings it will be
/// cooked for. Dates travel as `YYYY-MM-DD` strings on purpose — the web plan once
/// rendered every dinner a day early west of UTC by round-tripping through a `Date`.
struct PlanEntry: Codable, Identifiable, Hashable {
    var id: UUID
    var date: String
    var meal: String
    var scaledYield: Int
    var recipeSlug: String
    var recipeTitle: String
    var gf: Bool

    enum CodingKeys: String, CodingKey {
        case id, date, meal, gf
        case scaledYield = "scaled_yield"
        case recipeSlug = "recipe_slug"
        case recipeTitle = "recipe_title"
    }
}

struct WeekPlan: Codable, Hashable {
    /// The Monday, `YYYY-MM-DD`.
    var week: String
    var entries: [PlanEntry]
}

struct PlanEntryCreate: Codable {
    var date: String
    var meal: String
    var recipeSlug: String
    var scaledYield: Int?

    enum CodingKeys: String, CodingKey {
        case date, meal
        case recipeSlug = "recipe_slug"
        case scaledYield = "scaled_yield"
    }
}

enum Meal: String, CaseIterable, Identifiable {
    case breakfast, lunch, dinner
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}
