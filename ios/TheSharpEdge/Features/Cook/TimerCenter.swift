import Combine
import Foundation
import UIKit
import UserNotifications

/// One cook timer, keyed by recipe step. Wall-clock based: `endAt` is a date, so a
/// timer that ran while the app was suspended is exactly as far along as the oven.
struct CookTimer: Codable, Equatable, Identifiable {
    var slug: String
    var title: String
    /// 0-based step index.
    var step: Int
    var total: TimeInterval
    /// Set while running; nil while paused or idle.
    var endAt: Date?
    /// Seconds left while paused (== total while idle).
    var left: TimeInterval
    /// Completion has been announced — never announce twice.
    var fired = false

    var id: String { CookTimer.id(slug: slug, step: step) }
    static func id(slug: String, step: Int) -> String { "\(slug)#\(step)" }

    var label: String { "\(title) · step \(step + 1)" }
    var isRunning: Bool { endAt != nil }

    func remaining(at now: Date) -> TimeInterval {
        guard let endAt else { return left }
        return max(0, endAt.timeIntervalSince(now))
    }
    func isDone(at now: Date) -> Bool { remaining(at: now) <= 0 }
    /// Never started or reset: not worth a tray row.
    func isIdle(at now: Date) -> Bool { endAt == nil && left >= total && !isDone(at: now) }
}

/// Seam for the system notification centre so tests never touch it.
protocol TimerNotifier {
    func requestAuthorization()
    func schedule(_ timer: CookTimer, at fireDate: Date)
    func cancel(id: String)
}

/// App-level timer store. Injected once at the root; cook mode and the tray both read
/// it, so a 40-minute braise keeps counting after the cook moves on to the salad.
@MainActor
final class TimerCenter: ObservableObject {
    @Published private(set) var timers: [CookTimer] = []
    /// Views render remaining time against this; the ticker advances it once a second.
    @Published private(set) var now: Date

    static let storageKey = "sharpedge.timers"

    private let clock: () -> Date
    private let defaults: UserDefaults
    private let notifier: TimerNotifier
    private var ticker: Timer?
    private var lifecycle: AnyCancellable?

    init(clock: @escaping () -> Date = Date.init,
         defaults: UserDefaults = .standard,
         notifier: TimerNotifier? = nil,
         ticking: Bool = true) {
        self.clock = clock
        self.defaults = defaults
        self.notifier = notifier ?? UserNotificationTimerNotifier()
        self.now = clock()
        self.timers = Self.load(from: defaults)
        guard ticking else { return }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Coming back from the background: settle up immediately, not next second.
        lifecycle = NotificationCenter.default
            .publisher(for: UIApplication.willEnterForegroundNotification)
            .sink { [weak self] _ in self?.tick() }
    }

    // MARK: reads

    func timer(slug: String, step: Int) -> CookTimer? {
        timers.first { $0.id == CookTimer.id(slug: slug, step: step) }
    }

    /// Running, paused mid-way, or finished and not yet dismissed.
    func active(at now: Date? = nil) -> [CookTimer] {
        let at = now ?? self.now
        return timers.filter { !$0.isIdle(at: at) }
    }

    // MARK: writes

    /// Find or create the timer for a step. Creating does not start it. A step whose
    /// duration changed (new recipe version) gets a fresh timer.
    @discardableResult
    func ensure(slug: String, title: String, step: Int, total: TimeInterval) -> CookTimer {
        if let existing = timer(slug: slug, step: step), existing.total == total { return existing }
        let fresh = CookTimer(slug: slug, title: title, step: step, total: total, endAt: nil, left: total)
        timers.removeAll { $0.id == fresh.id }
        timers.append(fresh)
        save()
        return fresh
    }

    func start(id: String) {
        let now = clock()
        guard let i = index(of: id), timers[i].endAt == nil, timers[i].left > 0 else { return }
        notifier.requestAuthorization()
        let fireDate = now.addingTimeInterval(timers[i].left)
        timers[i].endAt = fireDate
        timers[i].fired = false
        notifier.schedule(timers[i], at: fireDate)
        save()
    }

    func pause(id: String) {
        let now = clock()
        guard let i = index(of: id), let endAt = timers[i].endAt else { return }
        timers[i].left = max(0, endAt.timeIntervalSince(now))
        timers[i].endAt = nil
        notifier.cancel(id: id)
        save()
    }

    func reset(id: String) {
        guard let i = index(of: id) else { return }
        timers[i].endAt = nil
        timers[i].left = timers[i].total
        timers[i].fired = false
        notifier.cancel(id: id)
        save()
    }

    func remove(id: String) {
        timers.removeAll { $0.id == id }
        notifier.cancel(id: id)
        save()
    }

    /// Advance the clock; announce each completion exactly once.
    @discardableResult
    func tick() -> [CookTimer] {
        let now = clock()
        self.now = now
        var finished: [CookTimer] = []
        for i in timers.indices where !timers[i].fired && timers[i].isRunning && timers[i].isDone(at: now) {
            timers[i].fired = true
            finished.append(timers[i])
        }
        if !finished.isEmpty {
            save()
            announce()
        }
        return finished
    }

    // MARK: private

    private func index(of id: String) -> Int? { timers.firstIndex { $0.id == id } }

    private func save() {
        if let data = try? JSONEncoder().encode(timers) {
            defaults.set(data, forKey: Self.storageKey)
        }
    }

    private static func load(from defaults: UserDefaults) -> [CookTimer] {
        guard let data = defaults.data(forKey: storageKey),
              let list = try? JSONDecoder().decode([CookTimer].self, from: data) else { return [] }
        return list
    }

    /// In the foreground the scheduled notification still presents (see the delegate),
    /// which is the sound; this is the buzz.
    private func announce() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }
}

// MARK: - System notifications

/// A timer that ends while the iPad is locked has to be heard. Local notifications
/// are the only thing that fires from a suspended app, so every start schedules one
/// and every pause/reset/dismiss cancels it.
final class UserNotificationTimerNotifier: NSObject, TimerNotifier, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private var asked = false

    override init() {
        super.init()
        center.delegate = self
    }

    func requestAuthorization() {
        guard !asked else { return }
        asked = true
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func schedule(_ timer: CookTimer, at fireDate: Date) {
        let content = UNMutableNotificationContent()
        content.title = timer.label
        content.body = "Timer done."
        content.sound = .default
        content.interruptionLevel = .timeSensitive
        let seconds = max(1, fireDate.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        center.add(UNNotificationRequest(identifier: timer.id, content: content, trigger: trigger))
    }

    func cancel(id: String) {
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Present while the app is open too — the cook is looking at a different step,
    /// not at the timer.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .list])
    }
}
