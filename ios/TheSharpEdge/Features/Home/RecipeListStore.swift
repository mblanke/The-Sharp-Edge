import SwiftUI

@MainActor
final class RecipeListStore: ObservableObject {
    @Published var sections: [Grouping.CategorySection] = []
    @Published var allCards: [RecipeCard] = []
    @Published var isLoading = false
    @Published var error: String?
    /// The sidebar's search field. A hardware keyboard on an iPad had no way to
    /// find a recipe short of scrolling; this is the ⌘F the web's ⌘K answers to.
    @Published var query = ""

    private var gfOnly = false

    func load(_ source: DataSource, gfOnly: Bool) async {
        isLoading = true
        error = nil
        do {
            let cards = try await source.listRecipes()
            allCards = cards
            applyFilter(gfOnly: gfOnly)
            SpotlightIndex.reindex(cards)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func applyFilter(gfOnly: Bool) {
        self.gfOnly = gfOnly
        sections = Grouping.byCategory(Self.filter(allCards, gfOnly: gfOnly, query: query))
    }

    /// Re-applies the current GF choice with a changed query.
    func applyQuery() {
        applyFilter(gfOnly: gfOnly)
    }

    /// Whether the sidebar is showing a subset because of the search field.
    var isSearching: Bool { !TextFold.fold(query).isEmpty }

    /// Pure: the cards a query keeps, diacritic- and case-insensitive so "gurken"
    /// finds Gurkensalat and "visinata" finds vișinată. Every word must match
    /// somewhere in the title, category or meta line.
    /// `nonisolated`: pure over its arguments, so tests and any thread may call it.
    nonisolated static func filter(_ cards: [RecipeCard], gfOnly: Bool, query: String) -> [RecipeCard] {
        let base = gfOnly ? cards.filter { $0.gf } : cards
        let words = TextFold.fold(query).split(separator: " ").map(String.init)
        guard !words.isEmpty else { return base }
        return base.filter { card in
            let haystack = TextFold.fold([card.title, card.category, card.meta ?? ""].joined(separator: " "))
            return words.allSatisfy { haystack.contains($0) }
        }
    }
}
