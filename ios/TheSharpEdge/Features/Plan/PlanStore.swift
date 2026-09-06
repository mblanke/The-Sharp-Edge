import Foundation

@MainActor
final class PlanStore: ObservableObject {
    @Published var week: String = PlanWeek.monday()
    @Published var plan: WeekPlan = WeekPlan(week: PlanWeek.monday(), entries: [])
    @Published var isLoading = false
    @Published var error: String?
    /// The (date, meal) slot with a request in flight, so its row can say so.
    @Published var pendingSlot: String?
    @Published var pushing = false

    var days: [String] { PlanWeek.days(of: week) }

    func entry(_ date: String, _ meal: Meal) -> PlanEntry? {
        plan.entries.first { $0.date == date && $0.meal == meal.rawValue }
    }

    func entries(on date: String) -> [PlanEntry] {
        plan.entries.filter { $0.date == date }
    }

    func load(_ source: DataSource) async {
        isLoading = true
        error = nil
        do {
            plan = try await source.weekPlan(week)
            week = plan.week
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func shift(_ source: DataSource, by delta: Int) async {
        week = PlanWeek.shift(week, by: delta)
        await load(source)
    }

    func today(_ source: DataSource) async {
        week = PlanWeek.monday()
        await load(source)
    }

    /// Returns false when the server refused; the caller keeps its picker open.
    @discardableResult
    func add(_ source: DataSource, date: String, meal: Meal, recipe: RecipeCard) async -> Bool {
        pendingSlot = "\(date):\(meal.rawValue)"
        error = nil
        defer { pendingSlot = nil }
        do {
            plan = try await source.planUpsert(PlanEntryCreate(
                date: date, meal: meal.rawValue, recipeSlug: recipe.slug, scaledYield: nil))
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func remove(_ source: DataSource, _ entry: PlanEntry) async {
        // optimistic: the row disappears now and comes back only if the server says no
        let previous = plan
        plan.entries.removeAll { $0.id == entry.id }
        do {
            plan = try await source.planRemove(entry.id)
        } catch {
            plan = previous
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Undo for `remove`: the same slot, the same servings.
    func restore(_ source: DataSource, _ entry: PlanEntry) async {
        do {
            plan = try await source.planUpsert(PlanEntryCreate(
                date: entry.date, meal: entry.meal, recipeSlug: entry.recipeSlug, scaledYield: entry.scaledYield))
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Everything planned this week, at its scale, into the running list.
    func pushToShopping(_ source: DataSource) async -> Bool {
        pushing = true
        error = nil
        defer { pushing = false }
        do {
            _ = try await source.planPushToShopping(week: week)
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }
}
