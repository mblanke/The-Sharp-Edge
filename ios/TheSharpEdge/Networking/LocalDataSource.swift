import Foundation

/// A `DataSource` backed entirely by this device.
///
/// The fourth implementation of the protocol, alongside `APIClient`, `CachingDataSource`
/// and `SampleDataSource` — which is the point: hosting a notebook on the device is a
/// new backend, not a new architecture.
///
/// The premise is that recipes are tiny. The owner's whole corpus is about 51 KB, so
/// handing the app to somebody else does not need accounts on a shared server, an
/// `owner_id` on every row, or per-tenant slugs fighting the printed QR contract. It
/// needs a JSON directory.
///
/// It also settles the hardest constraint by topology rather than by code: a guest's
/// iPad has no route to the owner's cookbook corpus, because that corpus lives in the
/// owner's Qdrant behind the owner's tailnet. CLAUDE.md §1 says the private tier never
/// leaves the local deployment; here it cannot.
///
/// Everything a cook needs works: recipes, versions, scaling, cook mode, the shopping
/// list with aisle grouping, and dictation — all through the same fixture-pinned Domain
/// code the server mirrors. What does not work is the Library and Ask, which need that
/// corpus. Those throw `.localOnly`; the UI hides them entirely.
final class LocalDataSource: DataSource {

    private let store: LocalStore

    init(store: LocalStore = .shared) {
        self.store = store
        Task { await store.info() }     // stamp the notebook on first use
    }

    // MARK: - Recipes

    func listRecipes() async throws -> [RecipeCard] {
        await store.cards()
    }

    func recipe(_ slug: String) async throws -> RecipeFull {
        guard let full = try await store.recipe(slug).full else { throw APIError.notFound }
        return full
    }

    func versions(_ slug: String) async throws -> [VersionSummary] {
        // Newest first, matching the server's ordering.
        try await store.recipe(slug).versions
            .sorted { $0.version > $1.version }
            .map { VersionSummary(id: $0.id, version: $0.version, label: $0.label,
                                  isCurrent: $0.isCurrent, createdAt: $0.createdAt) }
    }

    func version(_ slug: String, _ n: Int) async throws -> VersionOut {
        guard let match = try await store.recipe(slug).versions.first(where: { $0.version == n })
        else { throw APIError.notFound }
        return match
    }

    func restoreVersion(_ slug: String, _ n: Int) async throws -> RecipeFull {
        try await store.restore(slug, version: n)
    }

    func scale(_ slug: String, target: Int) async throws -> ScaleResponse {
        let r = try await recipe(slug)
        return try ScalingEngine.offlineScaleResponse(r, target: target)
    }

    func updateRecipe(_ slug: String, _ body: RecipeUpdate) async throws -> RecipeFull {
        try await store.update(slug, body)
    }

    func createRecipe(_ body: RecipeCreate) async throws -> RecipeFull {
        try await store.create(body)
    }

    // MARK: - Text → structure
    // The same parser the server runs, pinned case for case by shared/fixtures.

    func parsePhoto(_ jpeg: Data) async throws -> PhotoDraft {
        throw APIError.localOnly("Photo import")
    }

    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient] {
        IngredientParse.parseLines(lines, lang: lang.rawValue, spoken: true)
    }

    func slug(for title: String) async throws -> SlugResponse {
        let slug = IngredientParse.slugify(title)
        let taken = await store.has(slug)
        return SlugResponse(slug: slug,
                            available: !slug.isEmpty && !taken,
                            valid: IngredientParse.isValidSlug(slug))
    }

    func category(for spoken: String, lang: CaptureLanguage) async throws -> String? {
        IngredientParse.matchCategory(spoken, lang: lang.rawValue)
    }

    // MARK: - Shopping

    func shoppingList() async throws -> [ShoppingItem] {
        await store.shopping()
    }

    func shoppingText() async throws -> String {
        ShoppingBasket(items: await store.shopping()).text()
    }

    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem] {
        let recipe = try await self.recipe(slug)
        var basket = ShoppingBasket(items: await store.shopping())
        let rows = ScalingEngine.scale(recipe.currentVersion.ingredients,
                                       baseYield: recipe.baseYield,
                                       targetYield: targetYield ?? recipe.baseYield)
        basket.add(rows, from: slug)
        await store.saveShopping(basket.items)
        return basket.items
    }

    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem {
        var basket = ShoppingBasket(items: await store.shopping())
        let updated = try basket.setChecked(id, checked)
        await store.saveShopping(basket.items)
        return updated
    }

    func removeShoppingItem(_ id: UUID) async throws {
        try await removeShoppingItems([id])
    }

    func removeShoppingItems(_ ids: [UUID]) async throws {
        var basket = ShoppingBasket(items: await store.shopping())
        basket.remove(ids)
        await store.saveShopping(basket.items)
    }

    func clearShopping(checkedOnly: Bool) async throws {
        var basket = ShoppingBasket(items: await store.shopping())
        basket.clear(checkedOnly: checkedOnly)
        await store.saveShopping(basket.items)
    }

    // MARK: - Library and Ask
    // Absent, not merely unavailable. These read the owner's private, copyrighted
    // cookbook corpus, which is not part of what gets shared (CLAUDE.md §1).

    func sourcePage(path: String, page: Int) async throws -> Data {
        throw APIError.localOnly("Opening a cookbook page")
    }

    func search(_ q: String, topK: Int) async throws -> [ChunkOut] {
        throw APIError.localOnly("Library search")
    }

    func libraryStatus() async throws -> LibraryStatus {
        throw APIError.localOnly("The library")
    }

    func conversations() async throws -> [ConversationSummary] {
        throw APIError.localOnly("Saved answers")
    }

    func conversation(_ id: UUID) async throws -> ConversationFull {
        throw APIError.localOnly("Saved answers")
    }

    func ask(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: APIError.localOnly("Ask")) }
    }

    // MARK: - Misc

    /// The notebook is on this device, so it is always reachable.
    func health() async throws -> Bool { true }

    /// A QR code encodes a URL on a server. There isn't one — and a code pointing at
    /// nothing is worse than no code, because it gets printed and glued into a notebook.
    func qrURL(_ slug: String) -> URL? { nil }
}
