import SwiftUI
import Combine

/// Owns the AppConfig and vends the active DataSource.
///
/// The data source used to be rebuilt by a Combine pipeline: three `@Published`
/// publishers merged, `.dropFirst(3)` to swallow their initial emissions, then a 150 ms
/// debounce. That had two problems. The literal `3` silently breaks the day a fourth
/// published property is added — it drops three *combined* events, not one per
/// publisher. And the debounce meant a caller that changed the config and immediately
/// read `dataSource` got the **previous** one, which is exactly why "Test connection" in
/// Settings was testing the old server.
///
/// Rebuilding is now explicit. `generation` increments on every rebuild so views can
/// re-run their `.task` without watching individual settings.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var dataSource: DataSource
    /// Bumped on every rebuild. Views key `.task(id:)` off this, so a mode switch
    /// reloads everything on screen — miss one and stale recipes look like data loss.
    @Published private(set) var generation = 0

    /// Whether the last read came from disk. Owned here so it survives data-source
    /// rebuilds and can be observed by any screen.
    let offline = OfflineState()

    /// The device-hosted notebook. Held here rather than reached for as a singleton so
    /// tests can point an environment at a scratch directory.
    let localStore: LocalStore

    private var cancellables: Set<AnyCancellable> = []

    init(config: AppConfig = AppConfig(), localStore: LocalStore = .shared) {
        self.config = config
        self.localStore = localStore
        self.dataSource = AppEnvironment.make(config, offline: offline, localStore: localStore)

        // Forward the config's own changes so views observing the environment redraw.
        config.objectWillChange
            .sink { [weak self] in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    /// Rebuild the data source now. Callers that then read `dataSource` see the new one.
    func rebuildDataSource() {
        dataSource = AppEnvironment.make(config, offline: offline, localStore: localStore)
        generation += 1
        objectWillChange.send()
    }

    private static func make(_ config: AppConfig, offline: OfflineState,
                             localStore: LocalStore) -> DataSource {
        switch config.mode {
        case .local:
            // Deliberately ahead of the sample-data check: a DEBUG build in local mode
            // should show the real notebook, not fixtures.
            return LocalDataSource(store: localStore)

        case .server:
            if config.useSampleData { return SampleDataSource() }
            guard let url = config.baseURL else { return SampleDataSource() }
            // Wrapped so a dropped network serves the last known good copy rather than an
            // error screen. Writes are not cached — see CachingDataSource.
            let live = APIClient(base: url, tokenProvider: { Keychain.get() })
            return CachingDataSource(upstream: live, state: offline)
        }
    }
}
