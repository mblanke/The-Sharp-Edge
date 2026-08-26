import Foundation

/// Abstracts recipe/library/ask access so screens work identically against the live
/// backend or bundled sample fixtures.
protocol DataSource: AnyObject {
    func listRecipes() async throws -> [RecipeCard]
    func recipe(_ slug: String) async throws -> RecipeFull
    func versions(_ slug: String) async throws -> [VersionSummary]
    /// Full body of one past version — /versions carries metadata only.
    func version(_ slug: String, _ n: Int) async throws -> VersionOut
    /// Brings a past version back as a NEW version, so the restore is itself undoable.
    func restoreVersion(_ slug: String, _ n: Int) async throws -> RecipeFull
    func scale(_ slug: String, target: Int) async throws -> ScaleResponse
    func updateRecipe(_ slug: String, _ body: RecipeUpdate) async throws -> RecipeFull
    func createRecipe(_ body: RecipeCreate) async throws -> RecipeFull

    // Deterministic text→structure helpers, shared with web so both clients behave
    // identically. Unauthenticated; no model in the loop.
    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient]
    /// A photo of the cook's own page → structured draft, read by the local vision
    /// model on the server. Server mode only; local/sample throw `.localOnly`.
    func parsePhoto(_ jpeg: Data) async throws -> PhotoDraft
    /// A recipe's words in another language. Server mode only.
    func translate(_ body: TranslateRequest) async throws -> TranslateResponse
    /// A cached translation of a saved recipe, if one exists. Reading needs no token.
    func translation(_ slug: String, lang: String) async throws -> RecipeTranslation
    /// Make one and keep it, so later reads are instant.
    func makeTranslation(_ slug: String, lang: String) async throws -> RecipeTranslation
    func slug(for title: String) async throws -> SlugResponse
    func category(for spoken: String, lang: CaptureLanguage) async throws -> String?

    // Shopping list. Reads need no token so it opens on a phone in a shop;
    // writes need one, like every other write route.
    func shoppingList() async throws -> [ShoppingItem]
    func shoppingText() async throws -> String
    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem]
    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem
    func removeShoppingItem(_ id: UUID) async throws
    func removeShoppingItems(_ ids: [UUID]) async throws
    func clearShopping(checkedOnly: Bool) async throws

    func search(_ q: String, topK: Int) async throws -> [ChunkOut]
    /// One page of a source book as PDF bytes. Fetched rather than linked because the
    /// route needs the bearer token — it returns actual book content (CLAUDE.md §1).
    func sourcePage(path: String, page: Int) async throws -> Data
    func libraryStatus() async throws -> LibraryStatus
    func conversations() async throws -> [ConversationSummary]
    func conversation(_ id: UUID) async throws -> ConversationFull
    func ask(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error>

    func health() async throws -> Bool
    func qrURL(_ slug: String) -> URL?
}
