import XCTest
@testable import TheSharpEdge

/// Proves the test target exists, links the app, and can see internal types.
/// Everything in Stage 0 of the local-notebook work gates on this file compiling.
final class TargetSmokeTests: XCTestCase {

    func testTheTestTargetCanSeeTheAppModule() {
        // ScalingEngine is the app's own type; if this resolves, @testable import works.
        XCTAssertEqual(ScalingEngine.formatAmount(0.75, unit: "cup"), "¾ cup")
    }

    func testKitchenFractionsNeverRenderAsDecimals() {
        // CLAUDE.md §8: "0.75 is a bug; ¾ is correct."
        XCTAssertFalse(ScalingEngine.formatAmount(0.75, unit: "cup").contains("0.75"))
    }
}
