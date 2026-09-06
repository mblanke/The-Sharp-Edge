import Foundation

/// The meal plan as a value: every entry across every week, with the same slot rule
/// the server enforces (one recipe per date + meal; a new one replaces it). Backs the
/// device-hosted notebook and the sample data source, so both run the real logic.
struct PlanBook: Codable, Equatable {
    var entries: [PlanEntry] = []

    func week(_ monday: String) -> WeekPlan {
        let days = Set(PlanWeek.days(of: monday))
        let rows = entries
            .filter { days.contains($0.date) }
            .sorted { ($0.date, Meal(rawValue: $0.meal)?.order ?? 9) < ($1.date, Meal(rawValue: $1.meal)?.order ?? 9) }
        return WeekPlan(week: monday, entries: rows)
    }

    mutating func upsert(_ entry: PlanEntryCreate, recipe: RecipeFull) {
        entries.removeAll { $0.date == entry.date && $0.meal == entry.meal }
        entries.append(PlanEntry(
            id: UUID(),
            date: entry.date,
            meal: entry.meal,
            scaledYield: entry.scaledYield ?? recipe.baseYield,
            recipeSlug: recipe.slug,
            recipeTitle: recipe.title,
            gf: recipe.gf
        ))
    }

    /// Removes the entry and returns the Monday of the week it was in.
    @discardableResult
    mutating func remove(_ id: UUID) -> String? {
        guard let i = entries.firstIndex(where: { $0.id == id }) else { return nil }
        let date = entries[i].date
        entries.remove(at: i)
        return PlanWeek.date(date).map { PlanWeek.monday(of: $0) }
    }
}

private extension Meal {
    var order: Int {
        switch self {
        case .breakfast: return 0
        case .lunch: return 1
        case .dinner: return 2
        }
    }
}
