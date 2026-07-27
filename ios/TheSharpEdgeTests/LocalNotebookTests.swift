import XCTest
@testable import TheSharpEdge

/// The device-hosted notebook. These are the cases where a bug costs somebody their
/// recipes rather than merely annoying them.
final class LocalNotebookTests: XCTestCase {

    private var directory: URL!
    private var store: LocalStore!
    private var source: LocalDataSource!

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("notebook-test-\(UUID().uuidString)", isDirectory: true)
        store = LocalStore(directory: directory)
        source = LocalDataSource(store: store)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func draft(_ slug: String, title: String, category: String = "Soups & Stews",
                       ingredients: [Ingredient] = [Ingredient(amount: 2, unit: "lb", name: "beef chuck")],
                       status: String = "active") -> RecipeCreate {
        RecipeCreate(slug: slug, title: title, category: category, baseYield: 4,
                     yieldWord: "servings", status: status,
                     ingredients: ingredients,
                     steps: [Step(text: "Cook it.")], notes: [])
    }

    // MARK: - The backup rule

    /// The highest-consequence, lowest-visibility setting in the whole feature.
    /// `RecipeCache` excludes itself from backup because everything in it is
    /// re-fetchable. The notebook is the ONLY copy — inheriting that would mean a lost
    /// iPad takes a guest's recipes with it.
    func testTheNotebookIsIncludedInDeviceBackup() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let values = try directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, false,
                       "the notebook must be backed up — it is the user's only copy")
    }

    func testTheServerCacheIsStillExcludedFromBackup() throws {
        let cacheDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("cache-test-\(UUID().uuidString)", isDirectory: true)
        _ = RecipeCache(directory: cacheDir)
        defer { try? FileManager.default.removeItem(at: cacheDir) }
        let values = try cacheDir.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true,
                       "a re-fetchable cache should not consume iCloud quota")
    }

    // MARK: - Round trip

    func testARecipeSurvivesBeingWrittenAndReadBack() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))

        // A brand new store over the same directory — proves it came off disk.
        let reopened = LocalDataSource(store: LocalStore(directory: directory))
        let got = try await reopened.recipe("goulash")
        XCTAssertEqual(got.title, "Goulash")
        XCTAssertEqual(got.currentVersion.version, 1)
        XCTAssertEqual(got.currentVersion.ingredients.first?.name, "beef chuck")
    }

    func testDraftsAreKeptOutOfTheList() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.createRecipe(draft("wip", title: "Work in progress", status: "draft"))

        let cards = try await source.listRecipes()
        XCTAssertEqual(cards.map(\.slug), ["goulash"])
    }

    func testTheListIsOrderedByGlueInCategoryThenTitle() async throws {
        _ = try await source.createRecipe(draft("zzz-sauce", title: "Zzz Sauce",
                                                category: "Sauces & Salsas"))
        _ = try await source.createRecipe(draft("goulash", title: "Goulash",
                                                category: "Soups & Stews"))
        _ = try await source.createRecipe(draft("aaa-soup", title: "Aaa Soup",
                                                category: "Soups & Stews"))

        // Sauces sorts before Soups (CLAUDE.md §10 card order), titles within.
        let cards = try await source.listRecipes()
        XCTAssertEqual(cards.map(\.slug), ["zzz-sauce", "aaa-soup", "goulash"])
    }

    func testACollidingSlugIsRefusedTheSameWayTheServerRefusesIt() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        do {
            _ = try await source.createRecipe(draft("goulash", title: "Another Goulash"))
            XCTFail("expected a slug collision")
        } catch let error as APIError {
            guard case .slugTaken = error else { return XCTFail("wrong error: \(error)") }
        }
    }

    // MARK: - Append-only versions

    func testEditingAppendsAVersionRatherThanOverwriting() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.updateRecipe("goulash", RecipeUpdate(
            title: "Goulash (2009)",
            ingredients: [Ingredient(amount: 3, unit: "lb", name: "beef chuck")],
            steps: [Step(text: "Cook it longer.")], notes: []))

        let versions = try await source.versions("goulash")
        XCTAssertEqual(versions.map(\.version), [2, 1], "newest first")
        XCTAssertEqual(versions.filter(\.isCurrent).count, 1, "exactly one current version")
        XCTAssertTrue(versions.first { $0.version == 2 }!.isCurrent)

        // v1's body is still intact — that is the whole point of append-only.
        let v1 = try await source.version("goulash", 1)
        XCTAssertEqual(v1.ingredients.first?.amount, 2)
        let head = try await source.recipe("goulash")
        XCTAssertEqual(head.title, "Goulash (2009)")
    }

    func testRestoringAPastVersionIsItselfUndoable() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.updateRecipe("goulash", RecipeUpdate(
            ingredients: [Ingredient(amount: 9, unit: "lb", name: "beef chuck")],
            steps: [], notes: []))

        let restored = try await source.restoreVersion("goulash", 1)
        XCTAssertEqual(restored.currentVersion.version, 3, "restore appends, never rewinds")
        XCTAssertEqual(restored.currentVersion.ingredients.first?.amount, 2)
        XCTAssertEqual(restored.currentVersion.label, "restored v1")

        // v2 is still there, so the restore can itself be undone.
        let v2 = try await source.version("goulash", 2)
        XCTAssertEqual(v2.ingredients.first?.amount, 9)
    }

    func testRestoringTheCurrentVersionChangesNothing() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        let same = try await source.restoreVersion("goulash", 1)
        XCTAssertEqual(same.currentVersion.version, 1)
        let history = try await source.versions("goulash")
        XCTAssertEqual(history.count, 1)
    }

    func testAskingForAVersionThatNeverExistedIsNotFound() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        do {
            _ = try await source.version("goulash", 7)
            XCTFail("expected notFound")
        } catch let error as APIError {
            XCTAssertEqual(error, .notFound)
        }
    }

    // MARK: - Scaling and shopping, with no server anywhere

    func testScalingWorksWithNoServer() async throws {
        _ = try await source.createRecipe(draft(
            "goulash", title: "Goulash",
            ingredients: [Ingredient(amount: 2, unit: "lb", name: "beef chuck"),
                          Ingredient(amount: 0, unit: "", name: "salt")]))

        let scaled = try await source.scale("goulash", target: 8)
        XCTAssertEqual(scaled.ingredients.first?.display, "4 lb")
        // amount 0 stays an em dash and never scales (CLAUDE.md §5/§8).
        XCTAssertEqual(scaled.ingredients.last?.display, "—")
    }

    func testTheShoppingListPersistsAndAddsAcrossRecipes() async throws {
        _ = try await source.createRecipe(draft(
            "goulash", title: "Goulash",
            ingredients: [Ingredient(amount: 3, unit: "tbsp", name: "sweet Hungarian paprika"),
                          Ingredient(amount: 3, unit: "cup", name: "beef broth")]))
        _ = try await source.createRecipe(draft(
            "rub", title: "Rub", category: "Marinades",
            ingredients: [Ingredient(amount: 2, unit: "tbsp", name: "sweet Hungarian paprika")]))

        _ = try await source.addToShopping("goulash", targetYield: nil)
        _ = try await source.addToShopping("rub", targetYield: nil)

        // Reopen from disk: a shopping list you cannot close the app on is not a list.
        let reopened = LocalDataSource(store: LocalStore(directory: directory))
        let items = try await reopened.shoppingList()

        let paprika = try XCTUnwrap(items.first { $0.name.contains("paprika") })
        XCTAssertEqual(paprika.amount, 5, accuracy: 0.001, "a second recipe must ADD")
        XCTAssertEqual(paprika.aisle, "Herbs & spices")
        XCTAssertEqual(Set(paprika.recipes), ["goulash", "rub"])

        let broth = try XCTUnwrap(items.first { $0.name.contains("broth") })
        XCTAssertTrue(broth.checkGluten, "GF flags must survive on a device-only list")
    }

    // MARK: - Dictation, with no server anywhere

    func testDictatingARunOfIngredientsWorksOffline() async throws {
        let parsed = try await source.parseIngredients(
            ["two and a quarter cups flour one teaspoon salt two cups chocolate chips"],
            lang: .en)

        XCTAssertEqual(parsed.count, 3, "got \(parsed.map(\.name))")
        XCTAssertEqual(parsed[0].amount, 2.25, accuracy: 0.0001)
        XCTAssertEqual(parsed[0].name, "flour")
    }

    func testSlugGenerationKnowsWhatIsAlreadyTaken() async throws {
        _ = try await source.createRecipe(draft("mango-salsa", title: "Mango Salsa"))

        let taken = try await source.slug(for: "Mango Salsa")
        XCTAssertEqual(taken.slug, "mango-salsa")
        XCTAssertFalse(taken.available)

        let free = try await source.slug(for: "Vișinată")
        XCTAssertEqual(free.slug, "visinata")
        XCTAssertTrue(free.available)
        XCTAssertTrue(free.valid)
    }

    // MARK: - The corpus is not reachable from here

    /// CLAUDE.md §1: the cookbook shelf is private to the owner's deployment. On a
    /// device-hosted notebook there is no route to it at all, and every entry point
    /// must say so rather than returning something empty and plausible.
    func testLibraryAndAskAreUnreachableRatherThanEmpty() async throws {
        func expectLocalOnly(_ body: () async throws -> Void,
                             _ what: String, line: UInt = #line) async {
            do {
                try await body()
                XCTFail("\(what) should be unreachable on a local notebook", line: line)
            } catch let error as APIError {
                guard case .localOnly = error else {
                    return XCTFail("\(what): wrong error \(error)", line: line)
                }
            } catch {
                XCTFail("\(what): wrong error \(error)", line: line)
            }
        }

        await expectLocalOnly({ _ = try await self.source.search("onion soup", topK: 8) }, "search")
        await expectLocalOnly({ _ = try await self.source.libraryStatus() }, "libraryStatus")
        await expectLocalOnly({ _ = try await self.source.conversations() }, "conversations")
        await expectLocalOnly({ _ = try await self.source.conversation(UUID()) }, "conversation")

        do {
            for try await _ in source.ask(AskRequest(question: "how do I make espagnole?")) {
                XCTFail("ask should not stream anything on a local notebook")
            }
            XCTFail("ask should have thrown")
        } catch let error as APIError {
            guard case .localOnly = error else { return XCTFail("ask: wrong error \(error)") }
        }
    }

    /// A QR code points at a server URL. There isn't one, and a code that resolves to
    /// nothing is worse than no code — it gets printed and glued into a notebook.
    func testNoQRCodeIsOfferedWithoutAServer() {
        XCTAssertNil(source.qrURL("goulash"))
    }

    // MARK: - Durability

    func testACorruptRecipeFileLosesOnlyThatRecipe() async throws {
        _ = try await source.createRecipe(draft("goulash", title: "Goulash"))
        _ = try await source.createRecipe(draft("salsa", title: "Salsa",
                                                category: "Sauces & Salsas"))

        try Data("{ not json".utf8)
            .write(to: directory.appendingPathComponent("r-goulash.json"))

        let cards = try await source.listRecipes()
        XCTAssertEqual(cards.map(\.slug), ["salsa"],
                       "one unreadable file must not take the whole notebook down")
    }
}
