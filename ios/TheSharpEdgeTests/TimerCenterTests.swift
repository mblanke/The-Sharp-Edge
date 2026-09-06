import XCTest
@testable import TheSharpEdge

/// The timer math the cook acts on. Injected clock, scratch UserDefaults, no ticker,
/// and a spy in place of the notification centre.
@MainActor
final class TimerCenterTests: XCTestCase {
    private final class SpyNotifier: TimerNotifier {
        var scheduled: [(String, Date)] = []
        var cancelled: [String] = []
        var authorizations = 0
        func requestAuthorization() { authorizations += 1 }
        func schedule(_ timer: CookTimer, at fireDate: Date) { scheduled.append((timer.id, fireDate)) }
        func cancel(id: String) { cancelled.append(id) }
    }

    private var now = Date(timeIntervalSince1970: 1_000_000)
    private var defaults: UserDefaults!
    private var spy: SpyNotifier!

    override func setUp() {
        super.setUp()
        let suite = "TimerCenterTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
        spy = SpyNotifier()
    }

    private func makeCenter() -> TimerCenter {
        TimerCenter(clock: { self.now }, defaults: defaults, notifier: spy, ticking: false)
    }

    func testCountsDownOnWallClockAndSurvivesPauseResume() {
        let c = makeCenter()
        let t = c.ensure(slug: "stirfry", title: "Stir-fry", step: 0, total: 90)
        XCTAssertTrue(t.isIdle(at: now))

        c.start(id: t.id)
        now += 30
        c.tick()
        XCTAssertEqual(c.timer(slug: "stirfry", step: 0)!.remaining(at: now), 60, accuracy: 0.001)

        c.pause(id: t.id)
        now += 600   // paused: nothing moves
        XCTAssertEqual(c.timer(slug: "stirfry", step: 0)!.remaining(at: now), 60, accuracy: 0.001)

        c.start(id: t.id)
        now += 60
        XCTAssertTrue(c.timer(slug: "stirfry", step: 0)!.isDone(at: now))
    }

    func testABackgroundGapIsSettledOnTheNextTick() {
        // The app was suspended for 40 minutes; the braise did not wait for it.
        let c = makeCenter()
        let t = c.ensure(slug: "goulash", title: "Goulash", step: 4, total: 2400)
        c.start(id: t.id)
        now += 2400 + 5
        let finished = c.tick()
        XCTAssertEqual(finished.map(\.id), [t.id])
        XCTAssertEqual(c.tick(), [], "a completion is announced exactly once")
    }

    func testARestartedTimerFiresAgain() {
        let c = makeCenter()
        let t = c.ensure(slug: "a", title: "A", step: 0, total: 10)
        c.start(id: t.id)
        now += 11
        XCTAssertEqual(c.tick().count, 1)
        c.reset(id: t.id)
        XCTAssertTrue(c.timer(slug: "a", step: 0)!.isIdle(at: now))
        c.start(id: t.id)
        now += 11
        XCTAssertEqual(c.tick().count, 1)
    }

    func testPersistsAcrossLaunches() {
        let first = makeCenter()
        let t = first.ensure(slug: "goulash", title: "Goulash", step: 4, total: 2400)
        first.start(id: t.id)

        now += 600
        let second = makeCenter()
        let restored = second.timer(slug: "goulash", step: 4)
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored!.remaining(at: now), 1800, accuracy: 0.001)
        XCTAssertEqual(restored!.title, "Goulash")
    }

    func testSchedulesAndCancelsSystemNotifications() {
        let c = makeCenter()
        let t = c.ensure(slug: "a", title: "A", step: 2, total: 300)
        c.start(id: t.id)
        XCTAssertEqual(spy.authorizations, 1)
        XCTAssertEqual(spy.scheduled.count, 1)
        XCTAssertEqual(spy.scheduled[0].0, t.id)
        XCTAssertEqual(spy.scheduled[0].1, now.addingTimeInterval(300))

        c.pause(id: t.id)
        XCTAssertEqual(spy.cancelled, [t.id])
        c.start(id: t.id)
        XCTAssertEqual(spy.scheduled.count, 2)
        c.remove(id: t.id)
        XCTAssertEqual(spy.cancelled.count, 2)
        XCTAssertNil(c.timer(slug: "a", step: 2))
    }

    func testActiveHidesIdleTimers() {
        let c = makeCenter()
        c.ensure(slug: "a", title: "A", step: 0, total: 60)                 // idle
        c.start(id: c.ensure(slug: "a", title: "A", step: 1, total: 60).id) // running
        c.start(id: c.ensure(slug: "a", title: "A", step: 2, total: 60).id)
        now += 10
        c.pause(id: CookTimer.id(slug: "a", step: 2))                       // paused mid-way
        c.start(id: c.ensure(slug: "a", title: "A", step: 3, total: 5).id)
        now += 10                                                           // finished
        c.tick()
        XCTAssertEqual(c.active(at: now).map(\.step), [1, 2, 3])
    }

    func testADifferentDurationReplacesTheTimer() {
        let c = makeCenter()
        c.start(id: c.ensure(slug: "a", title: "A", step: 0, total: 60).id)
        let t = c.ensure(slug: "a", title: "A", step: 0, total: 90)
        XCTAssertEqual(t.total, 90)
        XCTAssertNil(t.endAt)
        XCTAssertEqual(c.timers.count, 1)
    }

    func testTimeStringRoundsUpSoTheDisplayNeverShowsZeroEarly() {
        XCTAssertEqual(CookTimerView.timeString(0), "0:00")
        XCTAssertEqual(CookTimerView.timeString(0.4), "0:01")
        XCTAssertEqual(CookTimerView.timeString(90), "1:30")
        XCTAssertEqual(CookTimerView.timeString(3661), "1:01:01")
    }
}

final class CookVoiceControlTests: XCTestCase {
    func testParsesTheKitchenVocabulary() {
        XCTAssertEqual(CookVoiceCommand.parse("okay next"), .next)
        XCTAssertEqual(CookVoiceCommand.parse("Next step"), .next)
        XCTAssertEqual(CookVoiceCommand.parse("go back"), .back)
        XCTAssertEqual(CookVoiceCommand.parse("say that again"), .repeatStep)
        XCTAssertEqual(CookVoiceCommand.parse("please start the timer"), .timerStart)
        XCTAssertEqual(CookVoiceCommand.parse("stop timer"), .timerPause)
        XCTAssertEqual(CookVoiceCommand.parse("reset timer"), .timerReset)
        XCTAssertNil(CookVoiceCommand.parse("how much paprika"))
        XCTAssertNil(CookVoiceCommand.parse(""))
    }

    func testAStreamFiresEachUtteranceOnce() {
        var stream = CookVoiceStream()
        XCTAssertNil(stream.commands(in: "ne"))
        XCTAssertEqual(stream.commands(in: "next"), .next)
        XCTAssertNil(stream.commands(in: "next"), "the same partial must not fire twice")
        XCTAssertNil(stream.commands(in: "next and then"), "words after a command are not a new command")
        XCTAssertEqual(stream.commands(in: "next and then back"), .back)
        // the recogniser restarted with a shorter transcript
        XCTAssertEqual(stream.commands(in: "next"), .next)
    }
}
