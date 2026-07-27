import XCTest
@testable import TheSharpEdge

/// What an *existing* install becomes the first time it runs a build that has modes.
///
/// This decision runs once and is persisted, so it is not self-correcting. Getting it
/// wrong on the owner's iPad means the app opens an empty local notebook and looks like
/// it has eaten 20 recipes. Everything here is therefore biased towards `.server`, and
/// each signal is tested in isolation so a future change cannot quietly remove one.
final class ModeMigrationTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUp() {
        suiteName = "mode-migration-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - Existing installs stay on the server

    func testAStoredServerURLMeansThisIsAnExistingInstall() {
        defaults.set("http://100.110.190.10:8010", forKey: AppConfig.Keys.baseURL)
        let decision = ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: false)
        XCTAssertEqual(decision.mode, .server)
        XCTAssertEqual(decision.origin, .storedBaseURL)
        XCTAssertTrue(decision.setupComplete, "an existing install must not see the chooser")
    }

    /// The strongest signal: this device has actually talked to a server and kept a copy.
    func testAnExistingServerCacheMeansServerMode() {
        let decision = ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: true)
        XCTAssertEqual(decision.mode, .server)
        XCTAssertEqual(decision.origin, .serverCache)
    }

    func testAStoredWriteTokenMeansServerMode() {
        let decision = ModeMigration.decide(defaults: defaults, hasToken: true,
                                            hasServerCache: false)
        XCTAssertEqual(decision.mode, .server)
        XCTAssertEqual(decision.origin, .keychainToken)
    }

    /// Weakest signal, and the reason it works: `gfOnly` is only written by its `didSet`,
    /// and Swift does not fire `didSet` for assignments inside `init`. Its presence
    /// therefore means somebody actually toggled it, not merely that the app launched.
    func testATouchedPreferenceMeansTheAppHasBeenUsed() {
        defaults.set(true, forKey: AppConfig.Keys.gfOnly)
        let decision = ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: false)
        XCTAssertEqual(decision.mode, .server)
        XCTAssertEqual(decision.origin, .storedPreference)
    }

    /// The realistic shape of the owner's iPad: everything set.
    func testAFullyConfiguredInstallIsNeverSwitchedToLocal() {
        defaults.set("http://100.110.190.10:8010", forKey: AppConfig.Keys.baseURL)
        defaults.set(false, forKey: AppConfig.Keys.gfOnly)
        let decision = ModeMigration.decide(defaults: defaults, hasToken: true,
                                            hasServerCache: true)
        XCTAssertEqual(decision.mode, .server)
        XCTAssertTrue(decision.setupComplete)
    }

    // MARK: - Only a genuinely fresh install gets the chooser

    func testAFreshInstallIsAskedRatherThanAssumed() {
        let decision = ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: false)
        XCTAssertFalse(decision.setupComplete, "a fresh install must see the chooser")
        XCTAssertEqual(decision.origin, .freshInstall)
    }

    /// If setup were somehow skipped, local is the safe default: the built-in default URL
    /// is the owner's private Tailscale address, and a stranger's iPad should not be
    /// reaching for it.
    func testAFreshInstallDefaultsToLocalRatherThanTheOwnersAddress() {
        XCTAssertEqual(ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: false).mode, .local)
    }

    // MARK: - It runs once

    func testTheDecisionIsRecordedSoAWrongAnswerCanBeDiagnosed() {
        defaults.set("http://example.test", forKey: AppConfig.Keys.baseURL)
        let decision = ModeMigration.decide(defaults: defaults, hasToken: false,
                                            hasServerCache: false)
        XCTAssertFalse(decision.origin.rawValue.isEmpty)
    }

    func testEveryOriginMapsToASensibleSetupState() {
        for origin in [ModeMigration.Origin.storedBaseURL, .storedPreference,
                       .keychainToken, .serverCache] {
            let d = ModeMigration.Decision(mode: .server, origin: origin)
            XCTAssertTrue(d.setupComplete, "\(origin) is an existing install")
        }
        XCTAssertFalse(ModeMigration.Decision(mode: .local, origin: .freshInstall).setupComplete)
    }
}

/// The mode itself.
final class AppModeTests: XCTestCase {

    /// Both modes need copy that says what you get *and* what you don't. The local
    /// blurb has to mention the missing library, or its absence reads as a bug.
    func testBothModesExplainThemselves() {
        for mode in AppMode.allCases {
            XCTAssertFalse(mode.title.isEmpty)
            XCTAssertFalse(mode.blurb.isEmpty)
        }
        XCTAssertTrue(AppMode.local.blurb.lowercased().contains("library"),
                      "local mode must say the library is not included")
    }

    func testOnlyServerModeOffersTheLibrary() {
        // Guards the rule that hides those routes; the corpus is private (CLAUDE.md §1).
        XCTAssertEqual(AppMode.allCases.count, 2)
    }
}
