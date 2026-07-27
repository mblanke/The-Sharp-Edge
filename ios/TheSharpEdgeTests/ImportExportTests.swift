import XCTest
@testable import TheSharpEdge

/// Moving recipes between notebooks.
///
/// This is what makes "share this with someone" mean sharing *recipes* rather than only
/// software. The risky part is import: a file that arrives by AirDrop must never quietly
/// overwrite something.
final class ImportExportTests: XCTestCase {

    private var directory: URL!
    private var store: LocalStore!
    private var source: LocalDataSource!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("io-test-\(UUID().uuidString)", isDirectory: true)
        store = LocalStore(directory: directory)
        source = LocalDataSource(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func draft(_ slug: String, title: String,
                       amount: Double = 2, category: String = "Soups & Stews") -> RecipeCreate {
        RecipeCreate(slug: slug, title: title, category: category, baseYield: 4,
                     yieldWord: "servings", status: "active",
                     ingredients: [Ingredient(amount: amount, unit: "lb", name: "beef chuck")],
                     steps: [Step(text: "Cook it.")], notes: [])
    }

    private func write(_ doc: NotebookDocument, named name: String = "x.sharpedge") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try doc.encoded().write(to: url)
        return url
    }

    // MARK: - Round trip

    func testARecipeSurvivesExportAndImportIntoAnotherNotebook() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let recipe = try await source.recipe("goulash")
        let file = try write(NotebookExport.current(recipe))

        // A different device entirely.
        let otherDir = directory.appendingPathComponent("other", isDirectory: true)
        let other = LocalStore(directory: otherDir)
        let otherSource = LocalDataSource(store: other)

        let plan = try await ImportService.plan(for: file, into: other)
        XCTAssertEqual(plan.rows.count, 1)
        XCTAssertEqual(plan.rows[0].resolution, .add, "no collision on an empty notebook")
        XCTAssertNil(plan.rows[0].existingTitle)

        let written = await ImportService.apply(plan, to: other)
        XCTAssertEqual(written, 1)

        let imported = try await otherSource.recipe("goulash")
        XCTAssertEqual(imported.title, "Goulash")
        XCTAssertEqual(imported.currentVersion.ingredients.first?.amount, 2)
        XCTAssertEqual(imported.category, "Soups & Stews")
        XCTAssertEqual(imported.currentVersion.version, 1)
    }

    func testAWholeNotebookRoundTrips() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.createRecipe(draft("salsa", title: "Salsa",
                                                category: "Sauces & Salsas"))
        let file = try write(await NotebookExport.everything(from: store))

        let otherDir = directory.appendingPathComponent("other2", isDirectory: true)
        let other = LocalStore(directory: otherDir)
        let plan = try await ImportService.plan(for: file, into: other)
        let written = await ImportService.apply(plan, to: other)
        XCTAssertEqual(written, 2)
        let slugs = await other.cards().map(\.slug).sorted()
        XCTAssertEqual(slugs, ["goulash", "salsa"])
    }

    /// Version history is renumbered from 1 on import so the imported book is
    /// self-consistent, with exactly one current version.
    func testImportedHistoryIsSelfConsistent() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.updateRecipe("goulash", RecipeUpdate(
            ingredients: [Ingredient(amount: 3, unit: "lb", name: "beef chuck")],
            steps: [], notes: []))
        let exported = try await NotebookExport.recipe("goulash", from: source)
        XCTAssertEqual(exported.recipes[0].versions.count, 2, "history should come along")

        let otherDir = directory.appendingPathComponent("other3", isDirectory: true)
        let other = LocalStore(directory: otherDir)
        let plan = try await ImportService.plan(for: try write(exported, named: "h.sharpedge"),
                                                into: other)
        _ = await ImportService.apply(plan, to: other)

        let landed = try await other.recipe("goulash")
        XCTAssertEqual(landed.versions.map(\.version), [1, 2])
        XCTAssertEqual(landed.versions.filter(\.isCurrent).count, 1)
        XCTAssertTrue(landed.versions.last!.isCurrent)
    }

    // MARK: - Collisions

    /// Rename is the default because slugs are a QR contract (CLAUDE.md §5): a recipe
    /// from somebody else's notebook is a different dish that happens to share a name.
    func testACollidingRecipeDefaultsToBeingAddedAsACopy() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "My Goulash"))
        let incoming = NotebookExport.current(RecipeFull(
            slug: "goulash", title: "Their Goulash", category: "Soups & Stews", meta: nil,
            baseYield: 4, yieldWord: "servings", gf: false, noscale: false, status: "active",
            source: nil,
            currentVersion: VersionOut(id: UUID(), version: 1, label: nil,
                                       ingredients: [Ingredient(amount: 9, unit: "lb", name: "beef chuck")],
                                       steps: [], notes: [], isCurrent: true, createdAt: Date())))

        let plan = try await ImportService.plan(for: try write(incoming), into: store)
        XCTAssertEqual(plan.rows[0].resolution, .rename)
        XCTAssertEqual(plan.rows[0].existingTitle, "My Goulash")
        XCTAssertEqual(plan.rows[0].freeSlug, "goulash-2")

        _ = await ImportService.apply(plan, to: store)

        // Both survive; nothing was overwritten.
        let mine = try await source.recipe("goulash")
        let theirs = try await source.recipe("goulash-2")
        XCTAssertEqual(mine.title, "My Goulash")
        XCTAssertEqual(theirs.title, "Their Goulash")
    }

    /// "They sent me a fixed goulash" — lossless, because append-only.
    func testImportingAsANewVersionKeepsWhatWasThere() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash", amount: 2))
        let incoming = NotebookExport.current(RecipeFull(
            slug: "goulash", title: "Goulash", category: "Soups & Stews", meta: nil,
            baseYield: 4, yieldWord: "servings", gf: false, noscale: false, status: "active",
            source: nil,
            currentVersion: VersionOut(id: UUID(), version: 1, label: nil,
                                       ingredients: [Ingredient(amount: 9, unit: "lb", name: "beef chuck")],
                                       steps: [Step(text: "Cook it longer.")], notes: [],
                                       isCurrent: true, createdAt: Date())))

        var plan = try await ImportService.plan(for: try write(incoming), into: store)
        XCTAssertTrue(plan.rows[0].options.contains(.addVersion))
        plan.rows[0].resolution = .addVersion
        _ = await ImportService.apply(plan, to: store)

        let after = try await source.recipe("goulash")
        XCTAssertEqual(after.currentVersion.version, 2)
        XCTAssertEqual(after.currentVersion.ingredients.first?.amount, 9)
        // The original is still there, so an unwanted import is undoable.
        let v1 = try await source.version("goulash", 1)
        XCTAssertEqual(v1.ingredients.first?.amount, 2)
    }

    func testReimportingTheSameFileDefaultsToSkipping() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let file = try write(NotebookExport.current(try await source.recipe("goulash")))

        let plan = try await ImportService.plan(for: file, into: store)
        XCTAssertEqual(plan.rows[0].resolution, .skip, "identical content: nothing to do")
        XCTAssertEqual(plan.willWrite, 0)
    }

    func testTwoIncomingRecipesWithTheSameSlugGetDistinctNames() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Mine"))
        let a = LocalRecipe(slug: "goulash", title: "A", category: "Soups & Stews", meta: nil,
                            baseYield: 4, yieldWord: "servings", gf: false, noscale: false,
                            status: "active", source: nil,
                            versions: [VersionOut(id: UUID(), version: 1, label: nil,
                                                  ingredients: [], steps: [], notes: [],
                                                  isCurrent: true, createdAt: Date())],
                            createdAt: Date(), updatedAt: Date())
        var b = a; b.title = "B"
        let doc = NotebookDocument(exportedAt: Date(), recipes: [a, b])

        let plan = try await ImportService.plan(for: try write(doc), into: store)
        let slugs = plan.rows.map(\.freeSlug)
        XCTAssertEqual(Set(slugs).count, 2, "two rows must not claim the same slug: \(slugs)")
        XCTAssertEqual(slugs, ["goulash-2", "goulash-3"])
    }

    // MARK: - Bad input

    func testARandomJSONFileIsRefusedClearly() async throws {
        let url = directory.appendingPathComponent("junk.sharpedge")
        try Data(#"{"hello":"world"}"#.utf8).write(to: url)
        do {
            _ = try await ImportService.plan(for: url, into: store)
            XCTFail("expected a refusal")
        } catch let error as NotebookDocument.ImportError {
            guard case .notANotebook = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    /// Best-effort decoding of a future format would silently drop whatever it did not
    /// understand — into somebody's permanent record.
    func testAFutureFormatIsRefusedRatherThanPartlyRead() async throws {
        var doc = NotebookDocument(exportedAt: Date(), recipes: [])
        doc.version = 99
        doc.recipes = [LocalRecipe(slug: "x", title: "X", category: "Pasta", meta: nil,
                                   baseYield: 4, yieldWord: "servings", gf: false,
                                   noscale: false, status: "active", source: nil,
                                   versions: [VersionOut(id: UUID(), version: 1, label: nil,
                                                         ingredients: [], steps: [], notes: [],
                                                         isCurrent: true, createdAt: Date())],
                                   createdAt: Date(), updatedAt: Date())]
        do {
            _ = try await ImportService.plan(for: try write(doc), into: store)
            XCTFail("expected a refusal")
        } catch let error as NotebookDocument.ImportError {
            guard case .tooNew = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    func testAnEmptyFileIsRefused() async throws {
        let doc = NotebookDocument(exportedAt: Date(), recipes: [])
        do {
            _ = try await ImportService.plan(for: try write(doc), into: store)
            XCTFail("expected a refusal")
        } catch let error as NotebookDocument.ImportError {
            guard case .empty = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - What must never be in an export

    /// CLAUDE.md §1: the cookbook corpus is private to the owner's deployment. An export
    /// is the one artefact that deliberately leaves the device, so it must carry recipes
    /// and nothing else — no citations, no chunks, no source paths.
    func testAnExportCarriesNoCorpusData() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let json = String(decoding: try await NotebookExport.everything(from: store).encoded(),
                          as: UTF8.self).lowercased()

        for forbidden in ["chunk", "citation", "source_path", "rerank", "qdrant",
                         "references_v2", "escoffier", "french laundry"] {
            XCTAssertFalse(json.contains(forbidden),
                           "export leaked corpus field \"\(forbidden)\"")
        }
    }

    func testTheFileNameIsUsefulWhenItLandsInFiles() async throws {
        _ = try await source.createRecipe(draft("mango-salsa", title: "Mango Salsa",
                                                category: "Sauces & Salsas"))
        let one = NotebookExport.current(try await source.recipe("mango-salsa"))
        XCTAssertEqual(one.suggestedFileName, "mango-salsa.sharpedge")

        // A one-recipe notebook is still one recipe, so it keeps the useful name.
        let single = await NotebookExport.everything(from: store)
        XCTAssertEqual(single.suggestedFileName, "mango-salsa.sharpedge")

        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let many = await NotebookExport.everything(from: store)
        XCTAssertEqual(many.suggestedFileName, "recipes.sharpedge")
    }
}
