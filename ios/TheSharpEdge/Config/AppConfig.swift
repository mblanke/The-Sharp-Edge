import Foundation
import Combine

/// App-wide configuration: server URL (UserDefaults), bearer token (Keychain),
/// GF-only filter (persisted), and the DEBUG sample-data toggle.
final class AppConfig: ObservableObject {
    private enum Keys {
        static let baseURL = "sharpedge.baseURL"
        static let gfOnly = "sharpedge.gfOnly"
        static let useSampleData = "sharpedge.useSampleData"
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
        token = Keychain.get() ?? ""
        #if DEBUG
        // Default ON in DEBUG so the app is fully explorable without the Tailscale backend.
        if d.object(forKey: Keys.useSampleData) == nil {
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
