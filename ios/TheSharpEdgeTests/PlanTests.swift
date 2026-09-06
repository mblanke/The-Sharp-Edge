import XCTest
@testable import TheSharpEdge

/// The plan's calendar arithmetic and slot rule. Dates are strings at every boundary
/// because the web plan once put every dinner a day early west of UTC.
final class PlanWeekTests: XCTestCase {
    private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testMondayOfAnyDayInTheWeek() {
        // 2026-09-06 is a Sunday; its ISO week starts Monday 2026-08-31
        XCTAssertEqual(PlanWeek.monday(of: date(2026, 9, 6)), "2026-08-31")
        XCTAssertEqual(PlanWeek.monday(of: date(2026, 8, 31)), "2026-08-31")
        XCTAssertEqual(PlanWeek.monday(of: date(2026, 9, 7)), "2026-09-07")
    }

    func testSevenDaysFromTheMonday() {
        let days = PlanWeek.days(of: "2026-09-07")
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.first, "2026-09-07")
        XCTAssertEqual(days.last, "2026-09-13")
    }

    func testShiftAcrossAMonthAndAYear() {
        XCTAssertEqual(PlanWeek.shift("2026-09-07", by: 1), "2026-09-14")
        XCTAssertEqual(PlanWeek.shift("2026-09-07", by: -1), "2026-08-31")
        XCTAssertEqual(PlanWeek.shift("2026-12-28", by: 1), "2027-01-04")
    }

    func testIsoRoundTripsAtLocalMidnight() {
        // the exact failure mode: a local midnight must not become the previous day
        var c = DateComponents()
        c.year = 2026; c.month = 9; c.day = 7; c.hour = 0; c.minute = 0
        let midnight = Calendar.current.date(from: c)!
        XCTAssertEqual(PlanWeek.iso(midnight), "2026-09-07")
        XCTAssertEqual(PlanWeek.iso(PlanWeek.date("2026-09-07")!), "2026-09-07")
    }
}

final class PlanBookTests: XCTestCase {
    private var goulash: RecipeFull { SampleData.full("goulash")! }
    private var salad: RecipeFull { SampleData.full("watermelon-feta")! }

    func testOneRecipePerSlotAndTheNewOneWins() {
        var book = PlanBook()
        book.upsert(PlanEntryCreate(date: "2026-09-07", meal: "dinner", recipeSlug: "goulash", scaledYield: 8), recipe: goulash)
        book.upsert(PlanEntryCreate(date: "2026-09-07", meal: "dinner", recipeSlug: "watermelon-feta", scaledYield: nil), recipe: salad)
        let week = book.week("2026-09-07")
        XCTAssertEqual(week.entries.count, 1)
        XCTAssertEqual(week.entries[0].recipeSlug, "watermelon-feta")
        XCTAssertEqual(week.entries[0].scaledYield, salad.baseYield, "nil servings means the recipe's base")
    }

    func testAWeekOnlyShowsItsOwnDaysInMealOrder() {
        var book = PlanBook()
        book.upsert(PlanEntryCreate(date: "2026-09-07", meal: "dinner", recipeSlug: "goulash", scaledYield: nil), recipe: goulash)
        book.upsert(PlanEntryCreate(date: "2026-09-07", meal: "breakfast", recipeSlug: "watermelon-feta", scaledYield: nil), recipe: salad)
        book.upsert(PlanEntryCreate(date: "2026-09-14", meal: "lunch", recipeSlug: "goulash", scaledYield: nil), recipe: goulash)
        let week = book.week("2026-09-07")
        XCTAssertEqual(week.entries.map(\.meal), ["breakfast", "dinner"])
        XCTAssertEqual(book.week("2026-09-14").entries.count, 1)
        XCTAssertEqual(book.week("2026-09-21").entries.count, 0)
    }

    func testRemoveReportsTheWeekItCameFrom() {
        var book = PlanBook()
        book.upsert(PlanEntryCreate(date: "2026-09-16", meal: "dinner", recipeSlug: "goulash", scaledYield: nil), recipe: goulash)
        let id = book.week("2026-09-14").entries[0].id
        XCTAssertEqual(book.remove(id), "2026-09-14")
        XCTAssertNil(book.remove(id), "removing twice is a no-op")
        XCTAssertTrue(book.entries.isEmpty)
    }

    func testRoundTripsThroughJSON() throws {
        var book = PlanBook()
        book.upsert(PlanEntryCreate(date: "2026-09-07", meal: "dinner", recipeSlug: "goulash", scaledYield: 12), recipe: goulash)
        let data = try JSONEncoder().encode(book)
        XCTAssertEqual(try JSONDecoder().decode(PlanBook.self, from: data), book)
    }
}
