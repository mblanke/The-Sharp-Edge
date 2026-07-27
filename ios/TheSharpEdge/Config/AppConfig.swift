import Foundation
import Combine

/// App-wide configuration: server URL (UserDefaults), bearer token (Keychain),
/// GF-only filter (persisted), and the DEBUG sample-data toggle.
final class AppConfig: ObservableObject {
    /// Internal rather than private: `ModeMigration` reads these to tell an existing
    /// install from a fresh one, and it must look at the same keys this writes.
    enum Keys {
        static let baseURL = "sharpedge.baseURL"
        static let gfOnly = "sharpedge.gfOnly"
        static let useSampleData = "sharpedge.useSampleData"
        static let captureLanguage = "sharpedge.captureLanguage"
        static let mode = "sharpedge.mode"
        static let setupComplete = "sharpedge.setupComplete"
        static let modeOrigin = "sharpedge.modeOrigin"
    }

    /// Default backend over Tailscale (compose publishes api on host port 8010).
    static let defaultBaseURL = "http://100.110.190.10:8010"

    @Published var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: Keys.baseURL) }
    }

    @Published var gfOnly: Bool {
        didSet { UserDefaults.standard.set(gfOnly, forKey: Keys.gfOnly) }
    }

    /// When true, screens render from bundled fixtures instead of the network.
    @Published var useSampleData: Bool {
        didSet { UserDefaults.standard.set(useSampleData, forKey: Keys.useSampleData) }
    }

    /// Language the dictation screen opens in. Remembered because most households
    /// cook in one or two languages, not four.
    @Published var captureLanguage: CaptureLanguage {
        didSet { UserDefaults.standard.set(captureLanguage.rawValue, forKey: Keys.captureLanguage) }
    }

    /// Token is read/written through the Keychain, mirrored here only for UI binding.
    @Published var token: String {
        didSet {
            if token.isEmpty { Keychain.remove() } else { Keychain.set(token) }
        }
    }

    /// Where this device's recipes live. Changing it swaps the whole data source; it
    /// never moves or merges data (see `AppMode`).
    @Published var mode: AppMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: Keys.mode) }
    }

    /// False only on a genuinely fresh install, which is the one case that gets the
    /// first-run chooser.
    @Published var setupComplete: Bool {
        didSet { UserDefaults.standard.set(setupComplete, forKey: Keys.setupComplete) }
    }

    init() {
        let d = UserDefaults.standard

        // Decide the mode BEFORE the reads below can create any of the keys the decision
        // depends on. Persisted immediately: the heuristic must run exactly once, on the
        // first launch of a build that has modes, and never re-evaluate afterwards.
        if let stored = d.string(forKey: Keys.mode).flatMap(AppMode.init(rawValue:)) {
            mode = stored
            setupComplete = d.bool(forKey: Keys.setupComplete)
        } else {
            let decision = ModeMigration.decide(defaults: d)
            mode = decision.mode
            setupComplete = decision.setupComplete
            d.set(decision.mode.rawValue, forKey: Keys.mode)
            d.set(decision.setupComplete, forKey: Keys.setupComplete)
            d.set(decision.origin.rawValue, forKey: Keys.modeOrigin)
        }
        baseURLString = d.string(forKey: Keys.baseURL) ?? AppConfig.defaultBaseURL
        #if DEBUG
        // QA hook: point at an unreachable host to exercise the offline path without
        // taking the real server down.
        if let override = ProcessInfo.processInfo.environment["UITEST_BASE_URL"] {
            baseURLString = override
        }
        #endif
        gfOnly = d.bool(forKey: Keys.gfOnly)
        captureLanguage = CaptureLanguage(rawValue: d.string(forKey: Keys.captureLanguage) ?? "") ?? .en
        token = Keychain.get() ?? ""
        #if DEBUG
        // QA hook: the write token lives in the Keychain, which no simctl command can
        // seed. Without this there is no way to exercise a real save in the simulator —
        // every PUT comes back 401 and it looks like the editor is broken.
        if let t = ProcessInfo.processInfo.environment["UITEST_TOKEN"], !t.isEmpty {
            Keychain.set(t)
            token = t
        }
        #endif
        #if DEBUG
        // UITEST_LIVE=1 forces the real backend in a debug build. `simctl spawn defaults
        // write` does NOT reach an app's sandboxed UserDefaults, so this env hook is the
        // only reliable way to evaluate real search results in the simulator — without
        // it you are quietly looking at fixtures.
        if ProcessInfo.processInfo.environment["UITEST_LIVE"] == "1" {
            useSampleData = false
            d.set(false, forKey: Keys.useSampleData)
        } else if d.object(forKey: Keys.useSampleData) == nil {
            // Default ON in DEBUG so the app is explorable without the Tailscale backend.
            useSampleData = true
            d.set(true, forKey: Keys.useSampleData)
        } else {
            useSampleData = d.bool(forKey: Keys.useSampleData)
        }
        #else
        useSampleData = false
        #endif

        #if DEBUG
        applyUITestOverrides()
        #endif
    }

    var baseURL: URL? { URL(string: baseURLString) }

    /// Which signal decided the mode on this device. Diagnostic only — surfaced in
    /// Settings so a wrong answer can be explained rather than guessed at.
    var modeOrigin: String {
        UserDefaults.standard.string(forKey: Keys.modeOrigin) ?? "unknown"
    }

    /// Ask and the Library need the server's cookbook corpus (CLAUDE.md §1).
    var hasLibrary: Bool { mode == .server }

    #if DEBUG
    /// QA hooks matching the existing UITEST_* convention. Without them there is no way
    /// to reach the first-run path in the simulator, since it only fires once per install.
    func applyUITestOverrides() {
        let env = ProcessInfo.processInfo.environment
        if let raw = env["UITEST_MODE"], let m = AppMode(rawValue: raw) {
            mode = m
            setupComplete = true
        }
        if env["UITEST_SETUP"] == "1" { setupComplete = false }
    }
    #endif
}
