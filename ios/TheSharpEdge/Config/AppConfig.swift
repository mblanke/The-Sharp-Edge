import Foundation
import Combine

/// App-wide configuration: server URL (UserDefaults), bearer token (Keychain),
/// GF-only filter (persisted), and the DEBUG sample-data toggle.
final class AppConfig: ObservableObject {
    private enum Keys {
        static let baseURL = "sharpedge.baseURL"
        static let gfOnly = "sharpedge.gfOnly"
        static let useSampleData = "sharpedge.useSampleData"
        static let captureLanguage = "sharpedge.captureLanguage"
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

    init() {
        let d = UserDefaults.standard
        baseURLString = d.string(forKey: Keys.baseURL) ?? AppConfig.defaultBaseURL
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
    }

    var baseURL: URL? { URL(string: baseURLString) }
}
