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
    // Merging is the server's job (services/shopping.py). Offline we keep a simple
    // same-name/same-unit sum so the flow is explorable, and the real arithmetic —
    // unit families, kitchen fractions — is exercised against the live backend.
    private static var basket: [ShoppingItem] = []

    func shoppingList() async throws -> [ShoppingItem] { Self.basket }

    func shoppingText() async throws -> String {
        let lines = Self.basket.filter { !$0.checked }.map { item -> String in
            let flag = item.checkGluten ? "  (check GF)" : ""
            return "\(item.display) \(item.name)\(flag)"
        }
        return (["Shopping list", ""] + lines).joined(separator: "\n")
    }

    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem] {
        let recipe = try await self.recipe(slug)
        let target = targetYield ?? recipe.baseYield
        for row in ScalingEngine.scale(recipe.currentVersion.ingredients,
                                       baseYield: recipe.baseYield, targetYield: target) {
            let name = row.name
            if let i = Self.basket.firstIndex(where: {
                $0.name == name && $0.unit == row.ingredient.unit && !$0.toTaste
            }), row.scaledAmount > 0 {
                Self.basket[i].amount += row.scaledAmount
                Self.basket[i].display = ScalingEngine.formatAmount(Self.basket[i].amount,
                                                                    unit: Self.basket[i].unit)
                if !Self.basket[i].recipes.contains(slug) { Self.basket[i].recipes.append(slug) }
            } else if !Self.basket.contains(where: { $0.name == name }) {
                Self.basket.append(ShoppingItem(
                    id: UUID(), name: name, amount: row.scaledAmount,
                    unit: row.ingredient.unit, display: row.display,
                    toTaste: row.scaledAmount == 0, checked: false, recipes: [slug],
                    checkGluten: Self.hidesGluten(name)))
            }
        }
        return Self.basket
    }

    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem {
        guard let i = Self.basket.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
        Self.basket[i].checked = checked
        return Self.basket[i]
    }

    func removeShoppingItem(_ id: UUID) async throws {
        Self.basket.removeAll { $0.id == id }
    }

    func removeShoppingItems(_ ids: [UUID]) async throws {
        Self.basket.removeAll { ids.contains($0.id) }
    }

    func clearShopping(checkedOnly: Bool) async throws {
        Self.basket.removeAll { checkedOnly ? $0.checked : true }
    }

    private static let glutenWatch = [
        "paprika", "broth", "stock", "bouillon", "tomato paste", "soy sauce", "tamari",
        "worcestershire", "hoisin", "oyster sauce", "miso", "malt", "vinegar", "mustard",
    ]

    private static func hidesGluten(_ name: String) -> Bool {
        let probe = name.lowercased()
        return glutenWatch.contains { probe.contains($0) }
    }

    // Offline approximation of /parse/* — see OfflineParse. The server is canonical.
    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient] {
        lines
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .flatMap { OfflineParse.splitRun($0) }      // dictation carries no punctuation
            .map(OfflineParse.ingredient)
    }

    func slug(for title: String) async throws -> SlugResponse {
        let slug = OfflineParse.slug(title)
        let taken = SampleData.full(slug) != nil || Self.created[slug] != nil
        return SlugResponse(slug: slug, available: !slug.isEmpty && !taken, valid: !slug.isEmpty)
    }

    func category(for spoken: String, lang: CaptureLanguage) async throws -> String? {
        Category.match(spoken)
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
