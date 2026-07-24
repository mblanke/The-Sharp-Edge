import Foundation

/// Abstracts recipe/library/ask access so screens work identically against the live
/// backend or bundled sample fixtures.
protocol DataSource: AnyObject {
    func listRecipes() async throws -> [RecipeCard]
    func recipe(_ slug: String) async throws -> RecipeFull
    func versions(_ slug: String) async throws -> [VersionSummary]
    func scale(_ slug: String, target: Int) async throws -> ScaleResponse
    func updateRecipe(_ slug: String, _ body: RecipeUpdate) async throws -> RecipeFull

    func search(_ q: String, topK: Int) async throws -> [ChunkOut]
    func libraryStatus() async throws -> LibraryStatus
    func conversations() async throws -> [ConversationSummary]
    func conversation(_ id: UUID) async throws -> ConversationFull
    func ask(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error>

    func health() async throws -> Bool
    func qrURL(_ slug: String) -> URL?
}
