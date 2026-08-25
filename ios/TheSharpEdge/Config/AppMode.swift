import Foundation

/// Where this device's recipes live.
///
/// **Exactly one mode per device, and nothing syncs between them.** That is a deliberate
/// limit, not a missing feature: two writable copies of the same recipe with no shared
/// clock is a merge problem, and the honest version of "your iPad and the server
/// disagree about the goulash" is a conflict UI nobody wants in a kitchen. Switching
/// modes changes which notebook you are looking at; it does not move anything.
enum AppMode: String, Codable, CaseIterable {
    /// Recipes come from a Sharp Edge server, cached on disk for offline reading.
    case server
    /// Recipes live on this device. No server, and therefore no Library and no Ask.
    case local

    var title: String {
        switch self {
        case .server: return "Connect to a server"
        case .local: return "This iPad's own notebook"
        }
    }

    var blurb: String {
        switch self {
        case .server:
            return "Recipes come from your Sharp Edge server, with the cookbook library "
                 + "and Ask. A saved copy is kept on this iPad for cooking offline."
        case .local:
            return "Recipes live on this iPad. Scaling, versions, cook mode and the "
                 + "shopping list all work with no network. The cookbook library and "
                 + "Ask need a server and aren't part of this."
        }
    }
}

/// Deciding what an *existing* install should be, the first time it runs a build that
/// has modes at all.
///
/// This runs once and the answer is persisted, so getting it wrong is not
/// self-correcting — an owner whose iPad silently switched to an empty local notebook
/// would reasonably conclude the app had eaten 20 recipes. Everything here is therefore
/// biased towards `.server`, and which signal fired is recorded so a wrong answer can be
/// diagnosed instead of guessed at.
enum ModeMigration {

    /// Why a mode was chosen. Persisted for diagnosis, never shown in normal use.
    enum Origin: String {
        case storedBaseURL      // a server URL had been saved
        case storedPreference   // gfOnly had been written, so the app has been used
        case keychainToken      // a write token exists
        case serverCache        // this device has successfully fetched from a server
        case freshInstall       // no trace of prior use
    }

    struct Decision {
        let mode: AppMode
        let origin: Origin
        /// A fresh install has to choose; an existing one has already effectively chosen.
        var setupComplete: Bool { origin != .freshInstall }
    }

    /// Note `baseURLString` and `gfOnly` are assigned inside `AppConfig.init`, and Swift
    /// does not fire `didSet` for assignments in an initialiser — so on a genuinely fresh
    /// install neither key exists in UserDefaults. Their *presence* is therefore real
    /// evidence the app has been used, not an artefact of having launched once.
    static func decide(defaults: UserDefaults = .standard,
                       hasToken: Bool = Keychain.get()?.isEmpty == false,
                       hasServerCache: Bool = RecipeCache.shared.hasEverFetched) -> Decision {
        if defaults.object(forKey: AppConfig.Keys.baseURL) != nil {
            return Decision(mode: .server, origin: .storedBaseURL)
        }
        if hasServerCache {
            return Decision(mode: .server, origin: .serverCache)
        }
        if hasToken {
            return Decision(mode: .server, origin: .keychainToken)
        }
        if defaults.object(forKey: AppConfig.Keys.gfOnly) != nil {
            return Decision(mode: .server, origin: .storedPreference)
        }
        return Decision(mode: .local, origin: .freshInstall)
    }
}
