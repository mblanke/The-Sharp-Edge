import Foundation

/// Serves bundled fixtures so the app is fully explorable offline.
final class SampleDataSource: DataSource {
    /// Recipes created during this session, so the add-recipe flow completes end to end
    /// in the simulator. Process-lifetime only — nothing is persisted.
    private static var created: [String: RecipeFull] = [:]

    func listRecipes() async throws -> [RecipeCard] {
        try? await Task.sleep(nanoseconds: 120_000_000)
        let extras = Self.created.values
            .filter { $0.status == "active" }
            .map { RecipeCard(slug: $0.slug, title: $0.title, category: $0.category, meta: $0.meta,
                              baseYield: $0.baseYield, yieldWord: $0.yieldWord, gf: $0.gf,
                              noscale: $0.noscale, status: $0.status) }
        return SampleData.cards + extras
    }

    func recipe(_ slug: String) async throws -> RecipeFull {
        if let created = Self.created[slug] { return created }
        guard let r = SampleData.full(slug) else { throw APIError.notFound }
        return r
    }

    func versions(_ slug: String) async throws -> [VersionSummary] {
        guard let r = SampleData.full(slug) else { throw APIError.notFound }
        let v = r.currentVersion
        return [VersionSummary(id: v.id, version: v.version, label: v.label, isCurrent: true, createdAt: v.createdAt)]
    }

    func version(_ slug: String, _ n: Int) async throws -> VersionOut {
        guard let r = SampleData.full(slug) else { throw APIError.notFound }
        return r.currentVersion
    }

    func restoreVersion(_ slug: String, _ n: Int) async throws -> RecipeFull {
        try await recipe(slug)
    }

    func scale(_ slug: String, target: Int) async throws -> ScaleResponse {
        let r = try await recipe(slug)
        let rows = ScalingEngine.scale(r.currentVersion.ingredients, baseYield: r.baseYield, targetYield: target)
        let ingredients = try rows.map { row -> ScaledIngredient in
            let data = try JSONCoding.encoder.encode(ScaledIngredientDTO(
                amount: row.ingredient.amount, unit: row.ingredient.unit, name: row.name,
                note: row.note, section: row.section, scaledAmount: row.scaledAmount, display: row.display))
            return try JSONCoding.decoder.decode(ScaledIngredient.self, from: data)
        }
        return ScaleResponse(slug: slug, baseYield: r.baseYield, targetYield: target, yieldWord: r.yieldWord, ingredients: ingredients)
    }

    func updateRecipe(_ slug: String, _ body: RecipeUpdate) async throws -> RecipeFull {
        // Offline: echo an updated recipe with a bumped version so the editor flow is verifiable.
        let existing = try await recipe(slug)
        let newVersion = VersionOut(id: UUID(), version: existing.currentVersion.version + 1, label: body.label,
                                    ingredients: body.ingredients, steps: body.steps, notes: body.notes,
                                    isCurrent: true, createdAt: Date())
        return RecipeFull(slug: slug, title: body.title ?? existing.title, category: body.category ?? existing.category,
                          meta: body.meta ?? existing.meta, baseYield: body.baseYield ?? existing.baseYield,
                          yieldWord: body.yieldWord ?? existing.yieldWord, gf: body.gf ?? existing.gf,
                          noscale: body.noscale ?? existing.noscale, status: body.status ?? existing.status,
                          source: body.source ?? existing.source, currentVersion: newVersion)
    }

    func createRecipe(_ body: RecipeCreate) async throws -> RecipeFull {
        if SampleData.full(body.slug) != nil || Self.created[body.slug] != nil {
            throw APIError.slugTaken("Slug '\(body.slug)' already exists")
        }
        let version = VersionOut(id: UUID(), version: 1, label: body.label,
                                 ingredients: body.ingredients, steps: body.steps, notes: body.notes,
                                 isCurrent: true, createdAt: Date())
        let full = RecipeFull(slug: body.slug, title: body.title, category: body.category,
                              meta: body.meta, baseYield: body.baseYield, yieldWord: body.yieldWord,
                              gf: body.gf, noscale: body.noscale, status: body.status,
                              source: body.source, currentVersion: version)
        Self.created[body.slug] = full
        return full
    }

    // MARK: - Shopping list (offline)
    // Runs the real arithmetic — ShoppingBasket → ShoppingMerge → Aisles, all pinned to
    // the server by shared/fixtures. This used to be a simple same-name/same-unit sum
    // with its own gluten list (drifted to 14 terms against the server's 23) and a
    // hardcoded aisle of "Other". Exercising the same code the local notebook uses is
    // the point: the DEBUG path is now a rehearsal, not an approximation.
    private static var basket = ShoppingBasket()

    func shoppingList() async throws -> [ShoppingItem] { Self.basket.items }

    func shoppingText() async throws -> String { Self.basket.text() }

    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem] {
        let recipe = try await self.recipe(slug)
        let target = targetYield ?? recipe.baseYield
        return Self.basket.add(
            ScalingEngine.scale(recipe.currentVersion.ingredients,
                                baseYield: recipe.baseYield, targetYield: target),
            from: slug)
    }

    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem {
        try Self.basket.setChecked(id, checked)
    }

    func removeShoppingItem(_ id: UUID) async throws {
        Self.basket.remove([id])
    }

    func removeShoppingItems(_ ids: [UUID]) async throws {
        Self.basket.remove(ids)
    }

    func clearShopping(checkedOnly: Bool) async throws {
        Self.basket.clear(checkedOnly: checkedOnly)
    }

    // The full parser, not an approximation — IngredientParse is fixture-pinned to
    // /parse/* case for case, so the DEBUG path behaves exactly like the server and like
    // a device-hosted notebook.
    func parsePhoto(_ jpeg: Data) async throws -> PhotoDraft {
        throw APIError.localOnly("Photo import")
    }

    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient] {
        IngredientParse.parseLines(lines, lang: lang.rawValue, spoken: true)
    }

    func slug(for title: String) async throws -> SlugResponse {
        let slug = IngredientParse.slugify(title)
        let taken = SampleData.full(slug) != nil || Self.created[slug] != nil
        return SlugResponse(slug: slug, available: !slug.isEmpty && !taken,
                            valid: IngredientParse.isValidSlug(slug))
    }

    func category(for spoken: String, lang: CaptureLanguage) async throws -> String? {
        IngredientParse.matchCategory(spoken, lang: lang.rawValue)
    }

    func sourcePage(path: String, page: Int) async throws -> Data {
        throw APIError.localOnly("Opening a cookbook page")
    }

    func search(_ q: String, topK: Int) async throws -> [ChunkOut] {
        try? await Task.sleep(nanoseconds: 250_000_000)
        return SampleData.searchHits(q)
    }

    func libraryStatus() async throws -> LibraryStatus { SampleData.libraryStatus }

    func conversations() async throws -> [ConversationSummary] {
        [ConversationSummary(id: UUID(), title: "How does Escoffier build an espagnole?", createdAt: Date(timeIntervalSince1970: 1_690_500_000))]
    }

    func conversation(_ id: UUID) async throws -> ConversationFull {
        ConversationFull(id: id, title: "How does Escoffier build an espagnole?", createdAt: Date(),
                         messages: [
                            MessageOut(id: UUID(), role: "user", content: "How does Escoffier build an espagnole?", citations: [], createdAt: Date()),
                            MessageOut(id: UUID(), role: "assistant", content: "A brown roux, brown stock and tomato, simmered and skimmed for hours [1].", citations: [Citation(n: 1, title: "Escoffier — Le Guide Culinaire", sourcePath: "Cooking/Escoffier.pdf", heading: "The Mother Sauces", page: 12)], createdAt: Date()),
                         ])
    }

    func ask(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        SampleData.askStream(req)
    }

    func health() async throws -> Bool { true }

    func qrURL(_ slug: String) -> URL? { nil }
}

/// Encodable helper mirroring ScaledIngredient's wire shape (that type is decode-only).
private struct ScaledIngredientDTO: Encodable {
    var amount: Double
    var unit: String
    var name: String
    var note: String?
    var section: String?
    var scaledAmount: Double
    var display: String

    enum CodingKeys: String, CodingKey {
        case amount, unit, name, note, section
        case scaledAmount = "scaled_amount"
        case display
    }
}
