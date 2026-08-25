import XCTest
@testable import TheSharpEdge

/// `ScalingEngine` is the oldest of the Swift/Python mirrors and the only one that was
/// already claimed to be bit-identical. Pinning it first proves the harness works
/// against code nobody suspects, before Stage 1 points it at fresh ports.
final class ScalingParityTests: XCTestCase {

    func testFormatAmountMatchesTheServer() {
        forEachCase("scaling.format_amount") { (id, args: ValueUnitArg, expect: String, _) in
            XCTAssertEqual(
                ScalingEngine.formatAmount(args.value, unit: args.unit), expect,
                "format_amount(\(args.value), \"\(args.unit)\") — case \(id)")
        }
    }

    /// CLAUDE.md §8: quantities render as unicode kitchen fractions, never decimals.
    func testNoScaledQuantityEverRendersADecimalPoint() {
        forEachCase("scaling.format_amount") { (id, args: ValueUnitArg, _: String, _) in
            let rendered = ScalingEngine.formatAmount(args.value, unit: args.unit)
            XCTAssertFalse(rendered.contains("."), "\(id) rendered a decimal: \(rendered)")
        }
    }
}

/// Guards the harness itself.
final class FixtureHygieneTests: XCTestCase {

    /// Mirrors `CONSUMED` in api/tests/test_parity_fixtures.py. A fixture that no Swift
    /// test reads is worse than no fixture — it looks like the port is covered.
    static let consumed: Set<String> = [
        "scaling.format_amount",
        "shopping.normalise_name",
        "shopping.check_gluten",
        "shopping.merge_lines",
        "shopping.as_text",
        "aisles.classify_aisle",
        "aisles.aisle_rank",
        "ingredients.strip_diacritics",
        "ingredients.normalise_spoken",
        "ingredients.parse_ingredient",
        "ingredients.split_run_on",
        "ingredients.slugify",
        "ingredients.match_category",
    ]

    func testFixtureDirectoryIsReachable() throws {
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: SharedFixtures.directory.path, isDirectory: &isDir)
        XCTAssertTrue(exists && isDir.boolValue, """
            Could not find shared/fixtures at \(SharedFixtures.directory.path).
            These tests read the source tree via #filePath and must run on a simulator.
            """)
    }

    func testEveryFixtureOnDiskIsConsumedBySomeTest() throws {
        let orphans = try SharedFixtures.allNames().subtracting(Self.consumed)
        XCTAssertTrue(orphans.isEmpty, """
            Fixture files with no Swift test reading them: \(orphans.sorted()).
            Add a test, or delete the file. Silent orphans are how the gluten list drifted.
            """)
    }

    func testEveryConsumedFixtureExists() throws {
        let missing = Self.consumed.subtracting(try SharedFixtures.allNames())
        XCTAssertTrue(missing.isEmpty, """
            Tests expect fixtures that do not exist: \(missing.sorted()).
            Run: python api/scripts/dump_fixtures.py
            """)
    }
}
