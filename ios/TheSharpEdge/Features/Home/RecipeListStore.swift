import SwiftUI

@MainActor
final class RecipeListStore: ObservableObject {
    @Published var sections: [Grouping.CategorySection] = []
    @Published var allCards: [RecipeCard] = []
    @Published var isLoading = false
    @Published var error: String?

    func load(_ source: DataSource, gfOnly: Bool) async {
        isLoading = true
        error = nil
        do {
            let cards = try await source.listRecipes()
            allCards = cards
            applyFilter(gfOnly: gfOnly)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func applyFilter(gfOnly: Bool) {
        let filtered = gfOnly ? allCards.filter { $0.gf } : allCards
        sections = Grouping.byCategory(filtered)
    }
}
