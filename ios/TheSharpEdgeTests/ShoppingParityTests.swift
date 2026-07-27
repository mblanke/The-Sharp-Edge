import XCTest
@testable import TheSharpEdge

/// Holds the Swift shopping-list port to the server's answers, case for case.
///
/// These are not "does the code run" tests. Local notebook mode removes the server from
/// the loop, so a divergence here is a cook buying the wrong thing — or, for the gluten
/// cases, a celiac household member eating something they shouldn't (CLAUDE.md §1).
final class ShoppingParityTests: XCTestCase {

    func testNormaliseNameMatchesTheServer() {
        forEachCase("shopping.normalise_name") { (id, args: NameArg, expect: String, _) in
            XCTAssertEqual(ShoppingMerge.normaliseName(args.name), expect,
                           "normalise_name(\"\(args.name)\") — case \(id)")
        }
    }

    func testGlutenFlagsMatchTheServer() {
        forEachCase("shopping.check_gluten") { (id, args: NameArg, expect: Bool, _) in
            let line = ShoppingMerge.Line(name: args.name, amount: 1, unit: "tbsp")
            XCTAssertEqual(line.checkGluten, expect,
                           "check_gluten(\"\(args.name)\") — case \(id)")
        }
    }

    func testMergedLinesMatchTheServer() {
        forEachCase("shopping.merge_lines") {
            (id, args: LinesArg, expect: [MergedLineExpect], tolerance) in
            let tol = tolerance ?? 0.001
            let got = ShoppingMerge.merge(args.lines.map {
                ShoppingMerge.Line(name: $0.name, amount: $0.amount, unit: $0.unit,
                                   toTaste: $0.amount == 0, recipes: [$0.recipe])
            })

            XCTAssertEqual(got.count, expect.count, "\(id): line count")
            guard got.count == expect.count else { return }

            for (line, want) in zip(got, expect) {
                XCTAssertEqual(line.name, want.name, "\(id): name")
                XCTAssertEqual(line.unit, want.unit, "\(id): unit for \(want.name)")
                XCTAssertEqual(line.amount, want.amount, accuracy: tol,
                               "\(id): amount for \(want.name)")
                // Rendered strings compare exactly — this is what a cook reads.
                XCTAssertEqual(line.display, want.display, "\(id): display for \(want.name)")
                XCTAssertEqual(line.toTaste, want.to_taste, "\(id): to_taste for \(want.name)")
                XCTAssertEqual(line.recipes, want.recipes, "\(id): recipes for \(want.name)")
                XCTAssertEqual(line.checkGluten, want.check_gluten,
                               "\(id): GLUTEN FLAG for \(want.name)")
                XCTAssertEqual(line.aisle, want.aisle, "\(id): aisle for \(want.name)")
            }
        }
    }

    func testShareTextMatchesTheServer() {
        forEachCase("shopping.as_text") { (id, args: LinesTextArg, expect: String, _) in
            var merged = ShoppingMerge.merge(args.lines.map {
                ShoppingMerge.Line(name: $0.name, amount: $0.amount, unit: $0.unit,
                                   toTaste: $0.amount == 0, recipes: [$0.recipe])
            })
            if args.group_by_aisle {
                // Swift's sort is not stable; Python's is. Keep first-appearance order
                // inside an aisle by sorting on (rank, original index).
                merged = merged.enumerated()
                    .sorted { a, b in
                        let ra = Aisles.rank(a.element.aisle), rb = Aisles.rank(b.element.aisle)
                        return ra == rb ? a.offset < b.offset : ra < rb
                    }
                    .map(\.element)
                XCTAssertEqual(ShoppingMerge.asText(merged, groupBy: { $0.aisle }), expect,
                               "as_text grouped — case \(id)")
            } else {
                XCTAssertEqual(ShoppingMerge.asText(merged), expect, "as_text — case \(id)")
            }
        }
    }
}

final class AisleParityTests: XCTestCase {

    func testAisleClassificationMatchesTheServer() {
        forEachCase("aisles.classify_aisle") { (id, args: NameArg, expect: String, _) in
            XCTAssertEqual(Aisles.classify(args.name), expect,
                           "classify_aisle(\"\(args.name)\") — case \(id)")
        }
    }

    func testAisleRankMatchesTheServer() {
        forEachCase("aisles.aisle_rank") { (id, args: AisleArg, expect: Int, _) in
            XCTAssertEqual(Aisles.rank(args.aisle), expect, "aisle_rank — case \(id)")
        }
    }

    /// The order list itself was hand-copied in four places before this port.
    func testWalkingOrderPutsFreshFirstAndUnknownLast() {
        XCTAssertEqual(Aisles.order.first, "Produce")
        XCTAssertEqual(Aisles.order.last, "Other")
        XCTAssertGreaterThan(Aisles.rank("Frozen"), Aisles.rank("Produce"))
        XCTAssertEqual(Aisles.rank("nonsense"), Aisles.order.count)
    }
}

final class TextFoldTests: XCTestCase {

    /// The app previously folded text three different ways, none matching Python.
    func testFoldingMatchesPythonNFKDBehaviour() {
        XCTAssertEqual(TextFold.fold("Crème Fraîche"), "creme fraiche")
        XCTAssertEqual(TextFold.fold("JALAPEÑO"), "jalapeno")
        XCTAssertEqual(TextFold.fold("vișinată"), "visinata")   // Romanian comma-below
        XCTAssertEqual(TextFold.fold("  olive    oil  "), "olive oil")
    }

    /// ß has no NFKD decomposition; parity depends on it surviving folding intact.
    func testSharpSSurvivesFoldingLikeInPython() {
        XCTAssertEqual(TextFold.stripDiacritics("Weißwein"), "Weißwein")
    }
}
