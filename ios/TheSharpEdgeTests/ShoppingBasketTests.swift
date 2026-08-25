import XCTest
@testable import TheSharpEdge

/// Behaviour of the on-device basket, beyond the pure merge arithmetic the fixtures pin.
///
/// The stated requirement was: *"if I'm adding multiple recipes and ingredients are
/// similar I need them to add, not replace each other."* These are the cases where that
/// promise could quietly break on the device even with a correct merge.
final class ShoppingBasketTests: XCTestCase {

    private func rows(_ specs: [(Double, String, String)]) -> [ScaledRow] {
        specs.map { amount, unit, name in
            ScaledRow(ingredient: Ingredient(amount: amount, unit: unit, name: name),
                      scaledAmount: amount,
                      display: ScalingEngine.formatAmount(amount, unit: unit))
        }
    }

    func testASecondRecipeAddsToALineRatherThanReplacingIt() {
        var basket = ShoppingBasket()
        basket.add(rows([(3, "tbsp", "sweet Hungarian paprika")]), from: "goulash")
        basket.add(rows([(2, "tbsp", "sweet Hungarian paprika")]), from: "rub")

        XCTAssertEqual(basket.items.count, 1)
        XCTAssertEqual(basket.items[0].amount, 5, accuracy: 0.001)
        XCTAssertEqual(basket.items[0].display, "5 tbsp")
        XCTAssertEqual(basket.items[0].recipes, ["goulash", "rub"])
    }

    /// You ticked paprika off in the shop; adding another recipe must not un-tick it or
    /// make it jump position by handing it a fresh identity.
    func testTickingSomethingOffSurvivesAddingAnotherRecipe() throws {
        var basket = ShoppingBasket()
        basket.add(rows([(3, "tbsp", "sweet Hungarian paprika"),
                         (2, "lb", "beef chuck, cubed")]), from: "goulash")
        let paprikaID = try XCTUnwrap(basket.items.first { $0.name.contains("paprika") }).id
        _ = try basket.setChecked(paprikaID, true)

        basket.add(rows([(2, "tbsp", "sweet Hungarian paprika")]), from: "rub")

        let paprika = try XCTUnwrap(basket.items.first { $0.name.contains("paprika") })
        XCTAssertEqual(paprika.id, paprikaID, "identity changed — the checkbox would reset")
        XCTAssertTrue(paprika.checked, "a ticked item came back unticked")
        XCTAssertEqual(paprika.amount, 5, accuracy: 0.001)
    }

    func testPreparationDoesNotSplitOneIngredientIntoTwoLines() {
        var basket = ShoppingBasket()
        basket.add(rows([(2, "lb", "beef chuck, cut into 1-inch cubes")]), from: "goulash")
        basket.add(rows([(1, "lb", "beef chuck, trimmed")]), from: "stew")

        XCTAssertEqual(basket.items.count, 1, "you buy beef chuck; the cut is not a second item")
        XCTAssertEqual(basket.items[0].amount, 3, accuracy: 0.001)
    }

    func testGlutenFlagsAndAislesAreSetOnTheDevice() throws {
        var basket = ShoppingBasket()
        basket.add(rows([(3, "cup", "beef broth"), (3, "", "yellow onions, diced")]),
                   from: "goulash")

        let broth = try XCTUnwrap(basket.items.first { $0.name.contains("broth") })
        XCTAssertTrue(broth.checkGluten, "broth routinely hides gluten (CLAUDE.md §1)")
        XCTAssertEqual(broth.aisle, "Pantry")

        let onions = try XCTUnwrap(basket.items.first { $0.name.contains("onions") })
        XCTAssertFalse(onions.checkGluten)
        XCTAssertEqual(onions.aisle, "Produce", "aisle was hardcoded to Other before the port")
    }

    func testShareTextIsGroupedAndOmitsWhatYouAlreadyPickedUp() throws {
        var basket = ShoppingBasket()
        basket.add(rows([(3, "", "yellow onions, diced"),
                         (2, "lb", "beef chuck, cubed"),
                         (3, "cup", "beef broth")]), from: "goulash")
        let onionsID = try XCTUnwrap(basket.items.first { $0.name.contains("onions") }).id
        _ = try basket.setChecked(onionsID, true)

        let text = basket.text()
        let body = text.split(separator: "\n").map(String.init)

        XCTAssertFalse(text.contains("yellow onions"), "checked items stay off the share text")
        XCTAssertTrue(body.contains("Meat & fish"))
        XCTAssertTrue(body.contains("Pantry"))
        XCTAssertTrue(text.contains("(check GF)"), "the broth should carry its GF warning")
        // Fresh before cupboard — the order you actually walk.
        XCTAssertLessThan(try XCTUnwrap(body.firstIndex(of: "Meat & fish")),
                          try XCTUnwrap(body.firstIndex(of: "Pantry")))
    }

    func testClearingCheckedItemsLeavesTheRest() throws {
        var basket = ShoppingBasket()
        basket.add(rows([(3, "", "limes"), (2, "lb", "beef chuck")]), from: "a")
        let limesID = try XCTUnwrap(basket.items.first { $0.name == "limes" }).id
        _ = try basket.setChecked(limesID, true)

        basket.clear(checkedOnly: true)
        XCTAssertEqual(basket.items.map(\.name), ["beef chuck"])
    }

    func testToTasteItemsNeverGainAQuantity() {
        var basket = ShoppingBasket()
        basket.add(rows([(0, "", "flaky salt")]), from: "a")
        basket.add(rows([(0, "", "flaky salt")]), from: "b")

        XCTAssertEqual(basket.items.count, 1)
        XCTAssertTrue(basket.items[0].toTaste)
        XCTAssertEqual(basket.items[0].display, "to taste")
    }
}
