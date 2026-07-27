import XCTest
@testable import TheSharpEdge

struct ParseLineArg: Decodable { let line: String; let lang: String; let spoken: Bool }
struct SpokenArg: Decodable { let text: String; let lang: String }
struct RunOnArg: Decodable { let line: String; let lang: String }
struct TitleArg: Decodable { let title: String }
struct TextArg: Decodable { let text: String }
struct CategoryArg: Decodable { let spoken: String; let lang: String }

struct ParsedExpect: Decodable {
    let amount: Double
    let unit: String
    let name: String
}

/// Holds the Swift ingredient parser to the server's answers across all four capture
/// languages.
///
/// This is the port that most needed pinning. What it produces goes straight into
/// somebody's permanent recipe record, and it replaced `OfflineParse`, which described
/// itself as covering only "the common shapes" and deliberately not the full lexicon.
final class IngredientParseTests: XCTestCase {

    func testStripDiacriticsMatchesTheServer() {
        forEachCase("ingredients.strip_diacritics") { (id, args: TextArg, expect: String, _) in
            XCTAssertEqual(IngredientParse.stripDiacritics(args.text), expect, "case \(id)")
        }
    }

    func testNormaliseSpokenMatchesTheServer() {
        forEachCase("ingredients.normalise_spoken") { (id, args: SpokenArg, expect: String, _) in
            XCTAssertEqual(IngredientParse.normaliseSpoken(args.text, lang: args.lang), expect,
                           "normalise_spoken(\"\(args.text)\", \(args.lang)) — case \(id)")
        }
    }

    func testParsedIngredientsMatchTheServer() {
        forEachCase("ingredients.parse_ingredient") {
            (id, args: ParseLineArg, expect: ParsedExpect, tolerance) in
            let got = IngredientParse.parse(args.line, lang: args.lang, spoken: args.spoken)
            XCTAssertEqual(got.name, expect.name, "name — case \(id): \"\(args.line)\"")
            XCTAssertEqual(got.unit, expect.unit, "unit — case \(id): \"\(args.line)\"")
            XCTAssertEqual(got.amount, expect.amount, accuracy: tolerance ?? 0.0001,
                           "amount — case \(id): \"\(args.line)\"")
        }
    }

    /// The reported bug, verbatim: "I dictated the entire recipe and it added it as one
    /// ingredient."
    func testRunOnSplittingMatchesTheServer() {
        forEachCase("ingredients.split_run_on") { (id, args: RunOnArg, expect: [String], _) in
            XCTAssertEqual(IngredientParse.splitRunOn(args.line, lang: args.lang), expect,
                           "split_run_on — case \(id)")
        }
    }

    func testSlugsMatchTheServer() {
        forEachCase("ingredients.slugify") { (id, args: TitleArg, expect: String, _) in
            XCTAssertEqual(IngredientParse.slugify(args.title), expect, "case \(id)")
        }
    }

    func testCategoryMatchingMatchesTheServer() {
        forEachCase("ingredients.match_category") { (id, args: CategoryArg, expect: String?, _) in
            XCTAssertEqual(IngredientParse.matchCategory(args.spoken, lang: args.lang), expect,
                           "match_category(\"\(args.spoken)\", \(args.lang)) — case \(id)")
        }
    }

    // MARK: - Properties the fixtures cannot express

    /// Every generated slug must satisfy the API's own pattern, or the recipe cannot be
    /// created and the QR contract (CLAUDE.md §5) has nothing to point at.
    func testEveryGeneratedSlugIsAcceptableToTheAPI() {
        for title in ["Mango Salsa", "Vișinată", "Family Spaghetti Sauce (2009)",
                      "Crème Brûlée", "Weißwein Sauce", "Grandma's Pancakes",
                      "Beef   ---   Stew"] {
            let slug = IngredientParse.slugify(title)
            XCTAssertTrue(IngredientParse.isValidSlug(slug),
                          "\"\(title)\" produced an invalid slug: \"\(slug)\"")
        }
    }

    /// A whole dictated recipe, end to end — the flow that failed with 2 of 12 ingredients.
    func testAWholeDictatedRecipeSplitsIntoSeparateIngredients() {
        let dictated = "two and a quarter cups flour one teaspoon baking soda "
            + "one teaspoon salt one cup butter three quarters cup sugar two eggs "
            + "two cups chocolate chips"
        let parsed = IngredientParse.parseLines([dictated], lang: "en", spoken: true)

        XCTAssertEqual(parsed.count, 7, "got \(parsed.map(\.name))")
        XCTAssertEqual(parsed[0].amount, 2.25, accuracy: 0.0001)
        XCTAssertEqual(parsed[0].unit, "cup")
        XCTAssertEqual(parsed[0].name, "flour")
        XCTAssertEqual(parsed.last?.name, "chocolate chips")
        // Nothing should carry a fraction word stranded in its name.
        for row in parsed {
            XCTAssertFalse(row.name.contains("and a"), "fraction stranded in \"\(row.name)\"")
        }
    }

    /// "to taste" is amount 0 by contract — an em dash that never scales (CLAUDE.md §5).
    func testToTasteAndPinchNeverCarryAQuantity() {
        for (line, lang) in [("black pepper to taste", "en"), ("a pinch of saffron", "en"),
                             ("une pincée de sel", "fr"), ("eine Prise Muskat", "de"),
                             ("un praf de sare", "ro"), ("piper după gust", "ro")] {
            let row = IngredientParse.parse(line, lang: lang, spoken: true)
            XCTAssertEqual(row.amount, 0, "\"\(line)\" should be to-taste, got \(row.amount)")
            XCTAssertEqual(row.unit, "")
        }
    }

    /// A *livre* and a *Pfund* are 500 g, not a pound. Getting this wrong is a 10% error
    /// on every French or German weight.
    func testHalfKiloUnitsAreNotPounds() {
        XCTAssertEqual(IngredientParse.parse("une livre de beurre", lang: "fr", spoken: true).amount,
                       500, accuracy: 0.001)
        XCTAssertEqual(IngredientParse.parse("ein Pfund Butter", lang: "de", spoken: true).amount,
                       500, accuracy: 0.001)
        XCTAssertEqual(IngredientParse.parse("1 lb beef", lang: "en", spoken: false).unit, "lb")
    }
}
