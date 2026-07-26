import Foundation

/// Bundled fixtures so every screen renders without the Tailscale backend.
/// Shapes mirror the API (amount 0 = to taste; single Double amounts; sections via `section`).
enum SampleData {
    static func version(_ ingredients: [Ingredient], _ steps: [Step], _ notes: [String], version: Int = 1, label: String? = nil, current: Bool = true) -> VersionOut {
        VersionOut(id: UUID(), version: version, label: label, ingredients: ingredients,
                   steps: steps, notes: notes, isCurrent: current, createdAt: Date(timeIntervalSince1970: 1_690_000_000))
    }

    static let recipes: [RecipeFull] = [goulash, watermelonFeta, salmonMango, cucumberDressing, celeriac, souvlaki, pancakes]

    static var cards: [RecipeCard] { recipes.map { card($0) } }

    static func card(_ r: RecipeFull) -> RecipeCard {
        RecipeCard(slug: r.slug, title: r.title, category: r.category, meta: r.meta,
                   baseYield: r.baseYield, yieldWord: r.yieldWord, gf: r.gf, noscale: r.noscale, status: r.status)
    }

    static func full(_ slug: String) -> RecipeFull? { recipes.first { $0.slug == slug } }

    // MARK: Recipes

    static let goulash = RecipeFull(
        slug: "goulash", title: "Gluten-Free Hungarian Beef Goulash", category: "Soups & Stews",
        meta: "Rich, paprika-forward beef stew thickened naturally with potatoes — no flour, no roux",
        baseYield: 6, yieldWord: "servings", gf: true, noscale: false, status: "active",
        source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 2, unit: "lb", name: "beef chuck, cut into 1-inch cubes"),
                Ingredient(amount: 3, unit: "tbsp", name: "vegetable oil or lard"),
                Ingredient(amount: 3, unit: "", name: "yellow onions, diced"),
                Ingredient(amount: 4, unit: "", name: "garlic cloves, minced"),
                Ingredient(amount: 3, unit: "tbsp", name: "sweet Hungarian paprika (certified GF)"),
                Ingredient(amount: 1, unit: "tsp", name: "smoked or hot paprika"),
                Ingredient(amount: 2, unit: "tbsp", name: "tomato paste"),
                Ingredient(amount: 3, unit: "cup", name: "beef broth (certified GF)"),
                Ingredient(amount: 1.5, unit: "lb", name: "Yukon Gold potatoes, cubed"),
                Ingredient(amount: 0, unit: "", name: "salt and black pepper, to taste"),
            ],
            [
                Step(text: "Sear the beef: pat dry, season with salt and pepper. Heat the oil in a heavy pot and brown the cubes in batches, ~8 minutes total. Set aside.", timerSeconds: 480),
                Step(text: "Sweat the aromatics: lower the heat, add onions and cook until soft and golden, about 10 minutes. Add garlic for the last minute."),
                Step(text: "Bloom the paprika: off the heat, stir in both paprikas and the tomato paste so they don't scorch."),
                Step(text: "Simmer: return the beef, add broth to cover, bring to a gentle simmer and cook covered until tender, about 1½ hours.", timerSeconds: 5400),
                Step(text: "Add potatoes and cook uncovered until they break down slightly and thicken the stew, ~30 minutes.", timerSeconds: 1800),
            ],
            ["Three hidden-gluten checkpoints: paprika, beef broth/bouillon, and tomato paste — all can carry barley or wheat.",
             "Better the next day; the potatoes keep thickening."]
        ))

    static let watermelonFeta = RecipeFull(
        slug: "watermelon-feta", title: "Watermelon-Feta-Mint Salad", category: "Salads",
        meta: "Side for ~15 · scale down freely", baseYield: 15, yieldWord: "servings",
        gf: true, noscale: false, status: "active", source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 1, unit: "", name: "large watermelon (10–12 lb), cubed"),
                Ingredient(amount: 1.75, unit: "lb", name: "block feta in brine, cubed or crumbled"),
                Ingredient(amount: 1, unit: "", name: "large bunch fresh mint, leaves torn"),
                Ingredient(amount: 2.5, unit: "", name: "limes, juiced"),
                Ingredient(amount: 0, unit: "", name: "olive oil, a light drizzle"),
                Ingredient(amount: 0, unit: "", name: "flaky salt and black pepper"),
            ],
            [
                Step(text: "Combine watermelon, feta and mint in a wide bowl."),
                Step(text: "Dress: squeeze over the lime, drizzle oil, season and toss gently."),
                Step(text: "Serve cold, within the hour so the melon stays crisp."),
            ],
            ["Salt draws water from the melon — dress just before serving."]
        ))

    static let salmonMango = RecipeFull(
        slug: "salmon-mango-salsa", title: "Seared Salmon with Mango Salsa", category: "Entrées",
        meta: "4 fillets · bright, fast weeknight main", baseYield: 4, yieldWord: "fillets",
        gf: true, noscale: false, status: "active", source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 4, unit: "", name: "salmon fillets, 170–200 g each", section: "Salmon"),
                Ingredient(amount: 1, unit: "tbsp", name: "olive oil", section: "Salmon"),
                Ingredient(amount: 1, unit: "", name: "lime, zested", section: "Salmon"),
                Ingredient(amount: 0, unit: "", name: "salt and pepper", section: "Salmon"),
                Ingredient(amount: 1, unit: "", name: "ripe mango, diced", section: "Mango salsa"),
                Ingredient(amount: 0.5, unit: "", name: "red onion, finely diced", section: "Mango salsa"),
                Ingredient(amount: 1, unit: "", name: "jalapeño, minced", section: "Mango salsa"),
                Ingredient(amount: 0, unit: "", name: "cilantro and lime juice, to taste", section: "Mango salsa"),
            ],
            [
                Step(text: "Make the salsa: toss mango, onion, jalapeño, cilantro and lime. Rest while you cook."),
                Step(text: "Season the salmon and sear skin-side down in hot oil, ~4 minutes, then flip for 2.", timerSeconds: 240),
                Step(text: "Plate the salmon and spoon the salsa over the top."),
            ],
            ["Any firm white fish works if salmon is unavailable."]
        ))

    static let cucumberDressing = RecipeFull(
        slug: "cucumber-dressing", title: "Creamy Cucumber-Wasabi Dressing", category: "Sauces & Salsas",
        meta: "Makes ~2 cups", baseYield: 2, yieldWord: "cups", gf: true, noscale: false, status: "active",
        source: "family recipe",
        currentVersion: version(
            [
                Ingredient(amount: 1, unit: "", name: "English cucumber, grated and squeezed dry"),
                Ingredient(amount: 0.75, unit: "cup", name: "Greek yogurt"),
                Ingredient(amount: 2, unit: "tbsp", name: "GF tamari"),
                Ingredient(amount: 1, unit: "tsp", name: "wasabi oil (check the label)"),
                Ingredient(amount: 0, unit: "", name: "salt, to taste"),
            ],
            [
                Step(text: "Whisk everything together and chill 30 minutes.", timerSeconds: 1800),
            ],
            ["Use GF tamari; wasabi oil formulations vary — check the label."]
        ))

    static let celeriac = RecipeFull(
        slug: "celeriac-puree", title: "Celeriac Purée", category: "Sides",
        meta: "Silky, metric measures", baseYield: 4, yieldWord: "servings", gf: true, noscale: false, status: "active",
        source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 900, unit: "g", name: "celeriac, peeled and cubed"),
                Ingredient(amount: 500, unit: "ml", name: "whole milk"),
                Ingredient(amount: 120, unit: "ml", name: "cream"),
                Ingredient(amount: 40, unit: "g", name: "butter"),
                Ingredient(amount: 0, unit: "", name: "salt, to taste"),
            ],
            [
                Step(text: "Simmer the celeriac in the milk until very tender, ~20 minutes.", timerSeconds: 1200),
                Step(text: "Blend with the cream and butter until glossy; season."),
            ],
            []
        ))

    static let souvlaki = RecipeFull(
        slug: "souvlaki-marinade", title: "Souvlaki Marinade", category: "Marinades",
        meta: "Enough for ~1.5 kg chicken or pork", baseYield: 1, yieldWord: "batches", gf: true, noscale: false, status: "active",
        source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 0.33, unit: "cup", name: "olive oil"),
                Ingredient(amount: 0.25, unit: "cup", name: "lemon juice"),
                Ingredient(amount: 4, unit: "", name: "garlic cloves, grated"),
                Ingredient(amount: 1, unit: "tbsp", name: "dried oregano"),
                Ingredient(amount: 1, unit: "tsp", name: "salt"),
            ],
            [
                Step(text: "Whisk and pour over the meat; marinate at least 2 hours or overnight."),
            ],
            []
        ))

    static let pancakes = RecipeFull(
        slug: "pancakes", title: "Buttermilk Pancakes", category: "Breakfast",
        meta: "Contains gluten · a Sunday standard", baseYield: 12, yieldWord: "pancakes",
        gf: false, noscale: false, status: "active", source: nil,
        currentVersion: version(
            [
                Ingredient(amount: 2, unit: "cup", name: "all-purpose flour"),
                Ingredient(amount: 2, unit: "tbsp", name: "sugar"),
                Ingredient(amount: 2, unit: "tsp", name: "baking powder"),
                Ingredient(amount: 2, unit: "cup", name: "buttermilk"),
                Ingredient(amount: 2, unit: "", name: "eggs"),
            ],
            [
                Step(text: "Whisk dry, whisk wet, combine until just lumpy."),
                Step(text: "Cook on a buttered griddle until bubbles set, then flip."),
            ],
            ["Not gluten-free — kept for the household's non-celiac cooks."]
        ))

    // MARK: Gluten guide (hidden-gluten reference)

    struct GuideSection: Identifiable { var h: String; var items: [String]; var id: String { h } }
    static let glutenGuide: [GuideSection] = [
        GuideSection(h: "At the grill", items: [
            "Shared grates carry crumbs from buns and marinades — scrub or foil a GF zone.",
            "Bottled BBQ and teriyaki sauces often contain barley malt or soy sauce.",
            "Serving utensils double-dipped between GF and gluten dishes.",
        ]),
        GuideSection(h: "Pantry traps", items: [
            "Soy sauce → swap for certified GF tamari.",
            "Wasabi oil / paste formulations vary — check the label.",
            "Worcestershire sauce is fermented with barley malt.",
        ]),
        GuideSection(h: "Goulash checkpoints", items: [
            "Paprika can be cut with wheat flour — buy certified GF.",
            "Beef broth / bouillon cubes frequently carry gluten.",
            "Tomato paste is usually safe but verify on shared lines.",
        ]),
    ]

    // MARK: Library + Ask fixtures

    static let libraryStatus = LibraryStatus(
        mounted: false, libraryDir: nil,
        books: [
            BookOut(name: "Escoffier — Le Guide Culinaire", kind: "file", sizeBytes: 4_200_000),
            BookOut(name: "McGee — On Food and Cooking", kind: "file", sizeBytes: 8_800_000),
        ],
        ragHealth: RagHealth(ok: true, count: 12480))

    static func searchHits(_ q: String) -> [ChunkOut] {
        [
            ChunkOut(text: "An espagnole is built on a brown roux and a well-caramelised mirepoix, moistened with brown stock and tomato, then simmered and skimmed for hours…",
                     sourcePath: "Cooking/Escoffier.pdf", title: "Escoffier — Le Guide Culinaire",
                     heading: "The Mother Sauces", page: 12, score: 0.71, rerankScore: 0.93),
            ChunkOut(text: "Reduction concentrates flavour and thickens by driving off water; a demi-glace is espagnole reduced by half with additional stock…",
                     sourcePath: "Cooking/Escoffier.pdf", title: "Escoffier — Le Guide Culinaire",
                     heading: "Reductions", page: 41, score: 0.66, rerankScore: 0.81),
            ChunkOut(text: "Browning (the Maillard reaction) begins in earnest above about 150°C, producing hundreds of new aroma compounds…",
                     sourcePath: "Cooking/McGee.pdf", title: "McGee — On Food and Cooking",
                     heading: "Heat & Flavour", page: 778, score: 0.6, rerankScore: 0.74),
        ]
    }

    /// A canned answer streamed as SSE-like events for the Ask screen in DEBUG.
    static func askStream(_ req: AskRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        let convId = UUID().uuidString
        let sources = searchHits(req.question)
        let answer = "An espagnole starts from a brown roux cooked to a deep hazelnut colour [1], moistened with brown stock and a little tomato, then simmered slowly and skimmed [1]. Reduce it with more stock and you reach a demi-glace [2]."
        let citations = [
            Citation(n: 1, title: sources[0].title, sourcePath: sources[0].sourcePath, heading: sources[0].heading, page: sources[0].page),
            Citation(n: 2, title: sources[1].title, sourcePath: sources[1].sourcePath, heading: sources[1].heading, page: sources[1].page),
        ]
        let srcOut = sources.enumerated().map { i, c in
            Source(n: i + 1, title: c.title, sourcePath: c.sourcePath, heading: c.heading, page: c.page, text: c.text)
        }
        return AsyncThrowingStream { continuation in
            let task = Task {
                func send(_ event: String, _ payload: Encodable) {
                    if let data = try? JSONCoding.encoder.encode(AnyEncodable(payload)),
                       let str = String(data: data, encoding: .utf8) {
                        continuation.yield(SSEEvent(event: event, data: str))
                    }
                }
                send("meta", AskMeta(conversationId: convId, chunks: sources.count))
                for word in answer.split(separator: " ") {
                    try? await Task.sleep(nanoseconds: 45_000_000)
                    if Task.isCancelled { break }
                    send("token", AskToken(t: String(word) + " "))
                }
                send("done", AskDone(citations: citations, sources: srcOut))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    #if DEBUG
    /// Canned dictation for the simulator, which has no usable microphone path.
    /// Real lines someone would say — including the ones that used to break the parser:
    /// German compound numerals, a decimal comma, French partitive "de", Romanian
    /// diacritics, and a "to taste" phrase in every language.
    static func dictation(_ language: CaptureLanguage, _ stage: Int) -> String {
        let scripts: [CaptureLanguage: [String]] = [
            .en: [
                "Smoked Paprika Butter",
                "sauces",
                """
                two and a half tablespoons smoked paprika. half a cup of soft butter. \
                one clove of garlic, grated. a pinch of saffron. sea salt to taste
                """,
                """
                Beat the butter until pale. Fold in the paprika and garlic. \
                Roll in parchment and chill for two hours
                """,
            ],
            .fr: [
                "Beurre Maître d'Hôtel",
                "sauces",
                """
                200 grammes de beurre. 2 cuillères à soupe de persil haché. \
                1,5 cuillères à café de jus de citron. une pincée de sel. poivre à votre goût
                """,
                """
                Travailler le beurre en pommade. Incorporer le persil et le citron. \
                Rouler en boudin et réserver au froid
                """,
            ],
            .de: [
                "Gurkensalat mit Dill",
                "salate",
                """
                zweieinhalb Salatgurken. 200 Gramm saure Sahne. \
                1,5 Esslöffel frischer Dill. eine Prise Salz. Pfeffer nach Geschmack
                """,
                """
                Die Gurken sehr dünn hobeln. Mit Salz bestreuen und zwanzig Minuten ziehen lassen. \
                Ausdrücken und mit der sauren Sahne und dem Dill vermengen
                """,
            ],
            .ro: [
                "Ciorbă de Perișoare",
                "ciorbe",
                """
                500 g de carne tocată. două linguri de orez. o linguriță de sare, după gust. \
                1,5 litri de supă de legume. un praf de piper
                """,
                """
                Amestecă bine carnea cu orezul. Formează perișoare mici. \
                Fierbe-le în supă timp de treizeci de minute
                """,
            ],
        ]
        let script = scripts[language] ?? scripts[.en]!
        return stage < script.count ? script[stage] : ""
    }
    #endif
}

/// Type-erasing Encodable wrapper for the sample SSE encoder.
struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void
    init(_ wrapped: Encodable) { encodeFunc = wrapped.encode }
    func encode(to encoder: Encoder) throws { try encodeFunc(encoder) }
}
