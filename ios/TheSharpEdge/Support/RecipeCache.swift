import Foundation

/// On-disk copy of whatever the app has successfully fetched **from a server**.
///
/// The premise of the app is that it is the calculator beside a paper notebook
/// (CLAUDE.md §1). A calculator that stops working when the fibre drops is not one —
/// and that is exactly what happened: the gateway went down and the iPad could not
/// read a recipe while sitting three metres from the server holding it.
///
/// The whole corpus is about 51 KB, so there is nothing to be clever about. Every
/// successful fetch is written to Application Support as JSON; every failed fetch
/// falls back to it. Scaling is already entirely client-side
/// (`Domain/ScalingEngine.swift`), so a cached recipe still scales with no network.
///
/// **This is a cache, not a notebook.** Everything in it is re-fetchable, so it is
/// excluded from backup. `LocalStore` is the opposite case and says so explicitly.
actor RecipeCache {
    static let shared = RecipeCache()

    private let store: JSONStore
    private let listFile = "recipes.json"

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("RecipeCache", isDirectory: true)
        // Re-fetchable from the server: do not consume the user's iCloud quota.
        store = JSONStore(directory: base, excludedFromBackup: true)
    }

    // MARK: - Recipe list

    func saveList(_ cards: [RecipeCard]) {
        store.write(cards, to: listFile)
    }

    func loadList() -> [RecipeCard]? {
        store.read([RecipeCard].self, from: listFile)
    }

    // MARK: - Individual recipes

    /// Slugs match `^[a-z0-9][a-z0-9-]*$` (CLAUDE.md §5), so they are already safe as
    /// filenames — no escaping needed, and no path traversal possible.
    private func name(for slug: String) -> String { "r-\(slug).json" }

    func save(_ recipe: RecipeFull) {
        store.write(recipe, to: name(for: recipe.slug))
    }

    func load(_ slug: String) -> RecipeFull? {
        store.read(RecipeFull.self, from: name(for: slug))
    }

    /// When the list itself is unavailable, fall back to whatever individual recipes
    /// have been viewed — better a partial kitchen than an empty one.
    func loadAllCached() -> [RecipeCard] {
        store.names(prefix: "r-")
            .compactMap { store.read(RecipeFull.self, from: $0) }
            .map { RecipeCard(slug: $0.slug, title: $0.title, category: $0.category, meta: $0.meta,
                              baseYield: $0.baseYield, yieldWord: $0.yieldWord, gf: $0.gf,
                              noscale: $0.noscale, status: $0.status) }
            .sorted { $0.title < $1.title }
    }

    var lastSaved: Date? { store.modified(listFile) }

    /// Whether this device has ever successfully talked to a server. Used by the
    /// first-run check to tell an existing install from a fresh one.
    nonisolated var hasEverFetched: Bool {
        FileManager.default.fileExists(atPath: store.url(listFile).path)
    }

    func clear() {
        store.removeAll()
    }
}
