import Foundation

/// One recipe as it lives on the device: the metadata plus **every** version.
///
/// The inner `VersionOut` is reused verbatim rather than redefined, which means its
/// snake_case `CodingKeys` apply — a stored file's `versions` array is byte-compatible
/// with the API wire format. That is what makes export and import cheap later.
struct LocalRecipe: Codable, Hashable {
    var schemaVersion: Int = 1
    var slug: String
    var title: String
    var category: String
    var meta: String?
    var baseYield: Int
    var yieldWord: String
    var gf: Bool
    var noscale: Bool
    var status: String
    var source: String?
    /// Append-only. Never reordered, never rewritten.
    var versions: [VersionOut]
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case slug, title, category, meta
        case baseYield = "base_yield"
        case yieldWord = "yield_word"
        case gf, noscale, status, source, versions
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var current: VersionOut? {
        versions.first(where: \.isCurrent) ?? versions.max(by: { $0.version < $1.version })
    }

    var card: RecipeCard {
        RecipeCard(slug: slug, title: title, category: category, meta: meta,
                   baseYield: baseYield, yieldWord: yieldWord, gf: gf,
                   noscale: noscale, status: status)
    }

    /// Nil when the recipe somehow has no versions at all — a file that corrupt is worth
    /// skipping rather than crashing the list.
    var full: RecipeFull? {
        guard let current else { return nil }
        return RecipeFull(slug: slug, title: title, category: category, meta: meta,
                          baseYield: baseYield, yieldWord: yieldWord, gf: gf,
                          noscale: noscale, status: status, source: source,
                          currentVersion: current)
    }
}

/// Metadata about the notebook itself. Small, but it gives imports and future schema
/// migrations something to key off.
struct NotebookInfo: Codable {
    var schemaVersion: Int = 1
    var notebookID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case notebookID = "notebook_id"
        case createdAt = "created_at"
    }
}

/// A recipe notebook hosted on this device.
///
/// The whole corpus is ~51 KB, which is what makes device-hosting the right answer to
/// "let someone else add their own recipes" — no accounts, no per-tenant slugs fighting
/// the printed QR contract, and no route by which a guest could reach the owner's
/// private cookbook corpus (CLAUDE.md §1).
///
/// **One file per recipe.** Small atomic writes, a corrupt file loses one recipe rather
/// than the book, and the file is very nearly the export payload already. The list is
/// derived by scanning the directory — with 20-odd recipes there is no reason to keep an
/// index, and no index means no index-consistency bugs.
///
/// **Included in backup**, unlike `RecipeCache`. This is the only copy that exists.
actor LocalStore {
    static let shared = LocalStore()

    private let store: JSONStore
    private let infoFile = "notebook.json"
    private let shoppingFile = "shopping.json"

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notebook", isDirectory: true)
        // NOT excluded: losing this loses the user's recipes outright.
        store = JSONStore(directory: base, excludedFromBackup: false)
    }

    // MARK: - Notebook

    @discardableResult
    func info() -> NotebookInfo {
        if let existing = store.read(NotebookInfo.self, from: infoFile) { return existing }
        let fresh = NotebookInfo(notebookID: UUID(), createdAt: Date())
        store.write(fresh, to: infoFile)
        return fresh
    }

    /// Whether anything has ever been written here. Used by first-run detection.
    nonisolated var exists: Bool {
        FileManager.default.fileExists(atPath: store.url(infoFile).path)
    }

    // MARK: - Recipes

    private func name(for slug: String) -> String { "r-\(slug).json" }

    func all() -> [LocalRecipe] {
        store.names(prefix: "r-").compactMap { store.read(LocalRecipe.self, from: $0) }
    }

    /// Active recipes as cards, ordered the way the server orders them: category rank
    /// (glue-in order, CLAUDE.md §10) then title.
    func cards(includeDrafts: Bool = false) -> [RecipeCard] {
        all()
            .filter { includeDrafts || $0.status == "active" }
            .map(\.card)
            .sorted { a, b in
                let ra = Category.rank(a.category), rb = Category.rank(b.category)
                return ra == rb ? a.title < b.title : ra < rb
            }
    }

    func recipe(_ slug: String) throws -> LocalRecipe {
        guard let found = store.read(LocalRecipe.self, from: name(for: slug)) else {
            throw APIError.notFound
        }
        return found
    }

    func has(_ slug: String) -> Bool { store.exists(name(for: slug)) }

    func save(_ recipe: LocalRecipe) {
        var copy = recipe
        copy.updatedAt = Date()
        store.write(copy, to: name(for: copy.slug))
    }

    func delete(_ slug: String) {
        store.remove(name(for: slug))
    }

    // MARK: - Writes (append-only)

    /// Create a recipe at version 1. Throws `.slugTaken` to match the server's 409.
    func create(_ body: RecipeCreate) throws -> RecipeFull {
        guard !has(body.slug) else {
            throw APIError.slugTaken("Slug '\(body.slug)' already exists")
        }
        let now = Date()
        let version = VersionOut(id: UUID(), version: 1, label: body.label,
                                 ingredients: body.ingredients, steps: body.steps,
                                 notes: body.notes, isCurrent: true, createdAt: now)
        let recipe = LocalRecipe(
            slug: body.slug, title: body.title, category: body.category, meta: body.meta,
            baseYield: body.baseYield, yieldWord: body.yieldWord, gf: body.gf,
            noscale: body.noscale, status: body.status, source: body.source,
            versions: [version], createdAt: now, updatedAt: now)
        save(recipe)
        guard let full = recipe.full else { throw APIError.notFound }
        return full
    }

    /// Every edit appends a version and marks it current — the same contract as the
    /// server's PUT. Nothing is ever overwritten, so any edit is undoable.
    func update(_ slug: String, _ body: RecipeUpdate) throws -> RecipeFull {
        var recipe = try self.recipe(slug)
        if let v = body.title { recipe.title = v }
        if let v = body.category { recipe.category = v }
        if let v = body.meta { recipe.meta = v }
        if let v = body.baseYield { recipe.baseYield = v }
        if let v = body.yieldWord { recipe.yieldWord = v }
        if let v = body.gf { recipe.gf = v }
        if let v = body.noscale { recipe.noscale = v }
        if let v = body.source { recipe.source = v }
        if let v = body.status { recipe.status = v }

        appendVersion(&recipe, label: body.label, ingredients: body.ingredients,
                      steps: body.steps, notes: body.notes)
        save(recipe)
        guard let full = recipe.full else { throw APIError.notFound }
        return full
    }

    /// Bring a past version back as a NEW version, so the restore is itself undoable.
    /// Restoring the current version is a no-op, matching the server.
    func restore(_ slug: String, version: Int) throws -> RecipeFull {
        var recipe = try self.recipe(slug)
        guard let source = recipe.versions.first(where: { $0.version == version }) else {
            throw APIError.notFound
        }
        if source.isCurrent {
            guard let full = recipe.full else { throw APIError.notFound }
            return full
        }
        appendVersion(&recipe, label: source.label ?? "restored v\(source.version)",
                      ingredients: source.ingredients, steps: source.steps,
                      notes: source.notes)
        save(recipe)
        guard let full = recipe.full else { throw APIError.notFound }
        return full
    }

    /// The single entry point that enforces append-only. Not a convention — a function,
    /// so there is no way to write a version without going through it.
    private func appendVersion(_ recipe: inout LocalRecipe, label: String?,
                               ingredients: [Ingredient], steps: [Step], notes: [String]) {
        let next = (recipe.versions.map(\.version).max() ?? 0) + 1
        for i in recipe.versions.indices { recipe.versions[i].isCurrent = false }
        recipe.versions.append(
            VersionOut(id: UUID(), version: next, label: label, ingredients: ingredients,
                       steps: steps, notes: notes, isCurrent: true, createdAt: Date()))
    }

    // MARK: - Shopping

    func shopping() -> [ShoppingItem] {
        store.read([ShoppingItem].self, from: shoppingFile) ?? []
    }

    func saveShopping(_ items: [ShoppingItem]) {
        store.write(items, to: shoppingFile)
    }

    // MARK: - Maintenance

    func clear() {
        store.removeAll()
    }
}
