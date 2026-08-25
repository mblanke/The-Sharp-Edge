import Foundation

/// Observable "are we on the real thing or a saved copy?" state, so screens can say
/// so quietly instead of showing an error.
@MainActor
final class OfflineState: ObservableObject {
    /// True when the last read came from disk because the network failed.
    @Published var servingCache = false
    /// When the recipe list was last successfully fetched.
    @Published var lastSynced: Date?
}

/// Wraps the live client so reads survive a network outage.
///
/// Reads: try the network, save what comes back, and fall back to disk on transport
/// failure. Writes are never faked — an edit that did not reach the server must fail
/// visibly, because silently "saving" into a cache would lose the change and look
/// like it worked. Scaling is client-side already, so a cached recipe still scales.
final class CachingDataSource: DataSource {
    private let upstream: DataSource
    private let cache: RecipeCache
    private let state: OfflineState

    init(upstream: DataSource, cache: RecipeCache = .shared, state: OfflineState) {
        self.upstream = upstream
        self.cache = cache
        self.state = state
    }

    /// Only a transport failure means "we are offline". A 404 or 401 is the server
    /// answering, and falling back to a stale copy would hide a real answer.
    private func isOffline(_ error: Error) -> Bool {
        if case .transport = error as? APIError { return true }
        return (error as? URLError) != nil
    }

    @MainActor private func markLive(synced: Date? = nil) {
        state.servingCache = false
        if let synced { state.lastSynced = synced }
    }

    @MainActor private func markCached() {
        state.servingCache = true
    }

    // MARK: - Reads, cached

    func listRecipes() async throws -> [RecipeCard] {
        do {
            let fresh = try await upstream.listRecipes()
            await cache.saveList(fresh)
            await markLive(synced: Date())
            return fresh
        } catch {
            guard isOffline(error) else { throw error }
            if let cached = await cache.loadList(), !cached.isEmpty {
                await markCached()
                return cached
            }
            let salvaged = await cache.loadAllCached()
            if !salvaged.isEmpty {
                await markCached()
                return salvaged
            }
            throw error
        }
    }

    func recipe(_ slug: String) async throws -> RecipeFull {
        do {
            let fresh = try await upstream.recipe(slug)
            await cache.save(fresh)
            await markLive()
            return fresh
        } catch {
            guard isOffline(error), let cached = await cache.load(slug) else { throw error }
            await markCached()
            return cached
        }
    }

    func versions(_ slug: String) async throws -> [VersionSummary] {
        try await upstream.versions(slug)
    }

    func version(_ slug: String, _ n: Int) async throws -> VersionOut {
        try await upstream.version(slug, n)
    }

    func restoreVersion(_ slug: String, _ n: Int) async throws -> RecipeFull {
        let restored = try await upstream.restoreVersion(slug, n)
        await cache.save(restored)
        return restored
    }

    /// Falls back to the local engine, which is a verbatim port of the server's
    /// (CLAUDE.md §8) — so the numbers are identical, not approximate.
    func scale(_ slug: String, target: Int) async throws -> ScaleResponse {
        do {
            return try await upstream.scale(slug, target: target)
        } catch {
            guard isOffline(error), let cached = await cache.load(slug) else { throw error }
            await markCached()
            return try ScalingEngine.offlineScaleResponse(cached, target: target)
        }
    }

    // MARK: - Writes, never faked

    func updateRecipe(_ slug: String, _ body: RecipeUpdate) async throws -> RecipeFull {
        let saved = try await upstream.updateRecipe(slug, body)
        await cache.save(saved)
        return saved
    }

    func createRecipe(_ body: RecipeCreate) async throws -> RecipeFull {
        let saved = try await upstream.createRecipe(body)
        await cache.save(saved)
        return saved
    }

    // MARK: - Straight through

    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient] {
        try await upstream.parseIngredients(lines, lang: lang)
    }
    func slug(for title: String) async throws -> SlugResponse { try await upstream.slug(for: title) }
    func parsePhoto(_ jpeg: Data) async throws -> PhotoDraft { try await upstream.parsePhoto(jpeg) }
    func category(for spoken: String, lang: CaptureLanguage) async throws -> String? {
        try await upstream.category(for: spoken, lang: lang)
    }
    func shoppingList() async throws -> [ShoppingItem] { try await upstream.shoppingList() }
    func shoppingText() async throws -> String { try await upstream.shoppingText() }
    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem] {
        try await upstream.addToShopping(slug, targetYield: targetYield)
    }
    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem {
        try await upstream.setShoppingChecked(id, checked)
    }
    func removeShoppingItem(_ id: UUID) async throws { try await upstream.removeShoppingItem(id) }
    func removeShoppingItems(_ ids: [UUID]) async throws { try await upstream.removeShoppingItems(ids) }
    func clearShopping(checkedOnly: Bool) async throws { try await upstream.clearShopping(checkedOnly: checkedOnly) }
    func search(_ q: String, topK: Int) async throws -> [ChunkOut] { try await upstream.search(q, topK: topK) }
    /// Not cached: a book page is only worth fetching when someone asks to read it, and
    /// caching pages of copyrighted books on the device is not something to do casually.
    func sourcePage(path: String, page: Int) async throws -> Data {
        try await upstream.sourcePage(path: path, page: page)
    }
    func libraryStatus() async throws -> LibraryStatus { try await upstream.libraryStatus() }
    func conversations() async throws -> [ConversationSummary] { try await upstream.conversations() }
    func conversation(_ id: UUID) async throws -> ConversationFull { try await upstream.conversation(id) }
    func ask(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error> { upstream.ask(req) }
    func health() async throws -> Bool { try await upstream.health() }
    func qrURL(_ slug: String) -> URL? { upstream.qrURL(slug) }
}
