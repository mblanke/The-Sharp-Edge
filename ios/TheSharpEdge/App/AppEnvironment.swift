import SwiftUI
import Combine

/// Owns the AppConfig and vends the active DataSource (live or sample), rebuilding it
/// whenever the server URL, token, or sample-data flag changes.
@MainActor
final class AppEnvironment: ObservableObject {
    @Published private(set) var config: AppConfig
    @Published private(set) var dataSource: DataSource
    /// Whether the last read came from disk. Owned here so it survives data-source
    /// rebuilds and can be observed by any screen.
    let offline = OfflineState()

    private var cancellables: Set<AnyCancellable> = []

    init(config: AppConfig = AppConfig()) {
        self.config = config
        self.dataSource = AppEnvironment.makeDataSource(config, offline: offline)

        // Rebuild the data source on any relevant config change.
        let urlChanges = config.$baseURLString.map { _ in () }.eraseToAnyPublisher()
        let tokenChanges = config.$token.map { _ in () }.eraseToAnyPublisher()
        let sampleChanges = config.$useSampleData.map { _ in () }.eraseToAnyPublisher()
        Publishers.MergeMany([urlChanges, tokenChanges, sampleChanges])
            .dropFirst(3) // ignore the initial @Published emissions
            .debounce(for: .milliseconds(150), scheduler: RunLoop.main)
        .sink { [weak self] in
            guard let self else { return }
            self.dataSource = AppEnvironment.makeDataSource(self.config, offline: self.offline)
            self.objectWillChange.send()
        }
        .store(in: &cancellables)
    }

    private static func makeDataSource(_ config: AppConfig, offline: OfflineState) -> DataSource {
        if config.useSampleData { return SampleDataSource() }
        guard let url = config.baseURL else { return SampleDataSource() }
        // Wrapped so a dropped network serves the last known good copy rather than an
        // error screen. Writes are not cached — see CachingDataSource.
        let live = APIClient(base: url, tokenProvider: { Keychain.get() })
        return CachingDataSource(upstream: live, state: offline)
    }
}
