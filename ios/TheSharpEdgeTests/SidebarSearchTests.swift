import XCTest
@testable import TheSharpEdge

/// The sidebar search is a pure filter over the loaded cards; it has to fold
/// diacritics the same way the rest of the app does, or a Romanian title is
/// unreachable from an English keyboard.
final class SidebarSearchTests: XCTestCase {
    private let cards = [
        RecipeCard(slug: "gurkensalat", title: "Gurkensalat", category: "Salads", meta: "German cucumber salad",
                   baseYield: 4, yieldWord: "servings", gf: true, noscale: false, status: "active"),
        RecipeCard(slug: "visinata", title: "Vișinată", category: "Drinks", meta: nil,
                   baseYield: 1, yieldWord: "bottle", gf: true, noscale: false, status: "active"),
        RecipeCard(slug: "goulash", title: "Beef Goulash", category: "Soups & Stews", meta: "Hungarian",
                   baseYield: 6, yieldWord: "servings", gf: true, noscale: false, status: "active"),
        RecipeCard(slug: "pancakes", title: "Classic Fluffy Pancakes", category: "Breakfast", meta: nil,
                   baseYield: 8, yieldWord: "pancakes", gf: false, noscale: false, status: "active")
    ]

    func testEmptyQueryKeepsEverything() {
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "   ").count, 4)
    }

    func testCaseAndDiacriticsAreIgnored() {
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "visinata").map(\.slug), ["visinata"])
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "GURKEN").map(\.slug), ["gurkensalat"])
    }

    func testMatchesCategoryAndMeta() {
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "hungarian").map(\.slug), ["goulash"])
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "drinks").map(\.slug), ["visinata"])
    }

    func testEveryWordMustMatch() {
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: false, query: "cucumber german").map(\.slug), ["gurkensalat"])
        XCTAssertTrue(RecipeListStore.filter(cards, gfOnly: false, query: "cucumber hungarian").isEmpty)
    }

    func testGFComposesWithTheQuery() {
        XCTAssertTrue(RecipeListStore.filter(cards, gfOnly: true, query: "pancakes").isEmpty)
        XCTAssertEqual(RecipeListStore.filter(cards, gfOnly: true, query: "beef").map(\.slug), ["goulash"])
    }
}
