import XCTest
@testable import TheSharpEdge

/// Pins PhotoDraft to the wire shape api/app/services/photo_import.py actually
/// emits — the fixture below is a real response from the deployed endpoint.
final class PhotoDraftTests: XCTestCase {
    private let fixture = """
    {
      "title": "Crêpes de Mamie",
      "meta": "Pour 4 personnes",
      "base_yield": 4,
      "yield_word": "personnes",
      "ingredients": [
        {"amount": 250.0, "unit": "g", "name": "farine", "section": null},
        {"amount": 500.0, "unit": "ml", "name": "lait", "section": null},
        {"amount": 0.0, "unit": "", "name": "sel", "section": null}
      ],
      "steps": [
        {"text": "Mélanger la farine et les oeufs", "timer_seconds": null},
        {"text": "Laisser reposer", "timer_seconds": 1800}
      ],
      "notes": []
    }
    """

    func testDecodesServerResponse() throws {
        let draft = try JSONCoding.decoder.decode(PhotoDraft.self, from: Data(fixture.utf8))
        XCTAssertEqual(draft.title, "Crêpes de Mamie")
        XCTAssertEqual(draft.baseYield, 4)
        XCTAssertEqual(draft.yieldWord, "personnes")
        XCTAssertEqual(draft.ingredients.count, 3)
        XCTAssertEqual(draft.ingredients[1].amount, 500)
        XCTAssertEqual(draft.ingredients[1].unit, "ml")
        XCTAssertEqual(draft.steps[1].timerSeconds, 1800)
    }

    func testMapsToRecipeCreateDraft() throws {
        let draft = try JSONCoding.decoder.decode(PhotoDraft.self, from: Data(fixture.utf8))
        let create = draft.toRecipeCreate(slug: "crepes-de-mamie")
        XCTAssertEqual(create.slug, "crepes-de-mamie")
        XCTAssertEqual(create.title, "Crêpes de Mamie")
        XCTAssertEqual(create.baseYield, 4)
        XCTAssertEqual(create.ingredients.count, 3)
        // to-taste survives the mapping (amount 0, celiac-adjacent rules downstream)
        XCTAssertEqual(create.ingredients[2].amount, 0)
        XCTAssertEqual(create.steps[1].timerSeconds, 1800)
    }
}
