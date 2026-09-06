import Foundation

/// Calendar arithmetic for the meal plan, in the cook's own calendar. Pure, so it is
/// unit-tested; every date is a `YYYY-MM-DD` string at the boundary because a `Date`
/// crossing UTC midnight is how the web plan lost a day.
enum PlanWeek {
    static var calendar: Calendar {
        var c = Calendar(identifier: .iso8601) // Monday-first
        c.timeZone = .current
        return c
    }

    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .iso8601)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func iso(_ date: Date) -> String { formatter.string(from: date) }

    static func date(_ iso: String) -> Date? { formatter.date(from: iso) }

    /// The Monday of the week containing `date`, as `YYYY-MM-DD`.
    static func monday(of date: Date = Date()) -> String {
        let cal = calendar
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let start = cal.date(from: comps) ?? date
        return iso(start)
    }

    /// Seven `YYYY-MM-DD` days starting at `week` (a Monday).
    static func days(of week: String) -> [String] {
        guard let start = date(week) else { return [] }
        let cal = calendar
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: start) }.map(iso)
    }

    /// The Monday `delta` weeks away.
    static func shift(_ week: String, by delta: Int) -> String {
        guard let start = date(week), let next = calendar.date(byAdding: .day, value: 7 * delta, to: start) else {
            return week
        }
        return iso(next)
    }

    static func label(_ iso: String, style: DateFormatter.Style = .medium) -> String {
        guard let d = date(iso) else { return iso }
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    static func isToday(_ iso: String) -> Bool { iso == self.iso(Date()) }
}
