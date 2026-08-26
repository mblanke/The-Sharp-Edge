import XCTest
@testable import TheSharpEdge

/// The lens shows another language over a recipe without altering it, and must
/// survive a translation that comes back shorter than the recipe.
@MainActor
final class TranslationLensTests: XCTestCase {
    private func store() -> RecipeDetailStore {
        let version = VersionOut(
            id: UUID(), version: 1, label: nil,
            ingredients: [Ingredient(amount: 500, unit: "g", name: "carne de vită"),
                          Ingredient(amount: 0, unit: "", name: "sare, piper")],
            steps: [Step(text: "Fierbe carnea.", timerSeconds: 3600)],
            notes: ["Mai bună a doua zi."], isCurrent: true, createdAt: Date())
        let recipe = RecipeFull(
            slug: "salata", title: "Salată de boeuf", category: "Salads", meta: nil,
            baseYield: 8, yieldWord: "servings", gf: false, noscale: false,
            status: "active", source: nil, currentVersion: version)
        let s = RecipeDetailStore()
        s.recipe = recipe
        s.target = 8
        s.english = RecipeTranslation(
            available: true, title: "Beef Salad", meta: nil,
            ingredients: [Ingredient(amount: 500, unit: "g", name: "beef"),
                          Ingredient(amount: 0, unit: "", name: "salt, pepper")],
            steps: [Step(text: "Boil the meat.", timerSeconds: 3600)],
            notes: ["Better the next day."])
        return s
    }

    func testLensIsOffUntilAskedFor() {
        let s = store()
        XCTAssertEqual(s.displayTitle, "Salată de boeuf")
        XCTAssertEqual(s.displayName("carne de vită"), "carne de vită")
        XCTAssertEqual(s.displayNotes, ["Mai bună a doua zi."])
    }

    func testLensSwapsWordsButNeverQuantities() {
        let s = store()
        s.readEnglish = true
        XCTAssertEqual(s.displayTitle, "Beef Salad")
        XCTAssertEqual(s.displayName("carne de vită"), "beef")
        XCTAssertEqual(s.displayStep(0, fallback: "Fierbe carnea."), "Boil the meat.")
        XCTAssertEqual(s.displayNotes, ["Better the next day."])
        // the recipe itself is untouched — quantities come from it, not the lens
        XCTAssertEqual(s.recipe?.currentVersion.ingredients[0].amount, 500)
        XCTAssertEqual(s.recipe?.currentVersion.ingredients[0].name, "carne de vită")
        XCTAssertEqual(s.scaledRows.first?.display, "500 g")
    }

    func testShortTranslationFallsBackInsteadOfCrashing() {
        let s = store()
        s.english = RecipeTranslation(available: true, title: "Beef Salad", meta: nil,
                                      ingredients: [], steps: [], notes: [])
        s.readEnglish = true
        XCTAssertEqual(s.displayName("carne de vită"), "carne de vită")
        XCTAssertEqual(s.displayStep(5, fallback: "Fierbe carnea."), "Fierbe carnea.")
    }
}
