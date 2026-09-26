import XCTest
@testable import TheSharpEdge

/// The same cases as `matchIngredients` in web/src/lib/cook.test.ts.
final class StepIngredientsTests: XCTestCase {
    private let goulash = [
        "beef chuck, cut into 1-inch cubes",
        "vegetable oil or lard",
        "yellow onions, diced",
        "sweet Hungarian paprika (certified GF)",
        "tomato paste",
        "beef broth (certified GF)",
        "Yukon Gold potatoes, cubed",
        "salt",
        "black pepper, to taste"
    ]

    func testKeywordsDropTheCommaTailParentheticalsAndStopwords() {
        XCTAssertEqual(StepIngredients.keywords("sweet Hungarian paprika (certified GF)"), ["sweet", "hungarian", "paprika"])
        XCTAssertEqual(StepIngredients.keywords("yellow onions, diced"), ["yellow", "onions"])
    }

    func testFindsIngredientsNamedInTheStep() {
        let hits = StepIngredients.match(step: "Sear the beef in batches, then soften the onions in the oil.", names: goulash)
        XCTAssertTrue(hits.contains(0))
        XCTAssertTrue(hits.contains(1))
        XCTAssertTrue(hits.contains(2))
        XCTAssertFalse(hits.contains(3))
    }

    func testSingularStepMatchesPluralName() {
        XCTAssertTrue(StepIngredients.match(step: "Add each onion whole.", names: goulash).contains(2))
    }

    func testNoMatchInsideLongerWords() {
        XCTAssertFalse(StepIngredients.match(step: "Bring the unsalted stock to a boil.", names: goulash).contains(7))
    }

    func testSimmerStep() {
        let hits = StepIngredients.match(step: "Stir in the paprika and tomato paste, then pour in the broth.", names: goulash)
        XCTAssertTrue(Set([3, 4, 5]).isSubset(of: hits))
    }
}
