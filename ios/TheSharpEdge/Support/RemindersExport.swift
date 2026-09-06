import EventKit
import Foundation

/// The shopping list into Apple Reminders: one reminder per unticked line, in a list
/// named after the app, so the phone and the watch carry it into the shop.
enum RemindersExport {
    static let listName = "Shopping · The Sharp Edge"

    enum ExportError: LocalizedError {
        case denied
        case noSource

        var errorDescription: String? {
            switch self {
            case .denied: return "Reminders access is off for this app. Turn it on in Settings → Privacy → Reminders."
            case .noSource: return "No Reminders account is available on this device."
            }
        }
    }

    /// Returns the number of reminders written.
    @discardableResult
    static func send(_ items: [ShoppingItem]) async throws -> Int {
        guard !items.isEmpty else { return 0 }
        let store = EKEventStore()
        guard try await store.requestFullAccessToReminders() else { throw ExportError.denied }

        let calendar = try list(in: store)
        for item in items {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            reminder.title = item.toTaste ? item.name : "\(item.display) \(item.name)"
            var notes: [String] = []
            if !item.recipes.isEmpty { notes.append("for " + item.recipes.joined(separator: ", ")) }
            if item.checkGluten { notes.append("check the label for gluten") }
            reminder.notes = notes.isEmpty ? nil : notes.joined(separator: "\n")
            try store.save(reminder, commit: false)
        }
        try store.commit()
        return items.count
    }

    private static func list(in store: EKEventStore) throws -> EKCalendar {
        if let existing = store.calendars(for: .reminder).first(where: { $0.title == listName }) {
            return existing
        }
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = listName
        guard let source = store.defaultCalendarForNewReminders()?.source
                ?? store.sources.first(where: { $0.sourceType == .local })
                ?? store.sources.first
        else { throw ExportError.noSource }
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }
}
