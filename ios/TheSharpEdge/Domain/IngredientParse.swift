import Foundation

/// Free-text and dictated ingredient lines → structured `{amount, unit, name}`.
///
/// A literal port of `api/app/services/ingredients.py`, pinned case-for-case by
/// `shared/fixtures/ingredients.*.json` (CLAUDE.md §14). It replaces `OfflineParse`,
/// which was explicitly "a compact stand-in… deliberately does not try to be the full
/// lexicon". That was fine while the server was always one network hop away. In local
/// notebook mode nothing else is going to parse the line, and what this produces is
/// written into somebody's permanent record.
///
/// Two entry points:
///
/// * `parse(line:)` — printed-text behaviour, byte-identical to the seed importer.
/// * `parse(line:lang:spoken: true)` — the dictation path. Runs `normaliseSpoken`
///   first, which rewrites everything language-specific into the English-canonical form
///   the core parser reads, then applies the pinch/to-taste rule.
///
/// The data model stays English-canonical: `unit` is always an allowed unit. Ingredient
/// *names* are left exactly as spoken — "200 g de farine" yields `name: "farine"`, not
/// "flour". Nothing is translated and no model is involved.
enum IngredientParse {

    // MARK: - Core (English) tables

    static let unitMap: [String: String] = [
        "tablespoon": "tbsp", "tablespoons": "tbsp", "tbsp": "tbsp",
        "teaspoon": "tsp", "teaspoons": "tsp", "tsp": "tsp",
        "cup": "cup", "cups": "cup",
        "pound": "lb", "pounds": "lb", "lb": "lb", "lbs": "lb",
        "ounce": "oz", "ounces": "oz", "oz": "oz",
        "g": "g", "gram": "g", "grams": "g",
        "kg": "kg", "kilogram": "kg", "kilograms": "kg",
        "ml": "ml",
        "l": "l", "liter": "l", "liters": "l", "litre": "l", "litres": "l",
        // Synthetic token. French *livre* and German *Pfund* are half-kilos, not pounds;
        // normaliseSpoken rewrites them to this so the conversion below catches them.
        "halfkilo": "halfkilo",
    ]

    /// Spec units are g/ml — convert metric multiples.
    static let metricFactor: [String: (String, Double)] = [
        "kg": ("g", 1000), "l": ("ml", 1000), "halfkilo": ("g", 500),
    ]

    static let num = #"(?:\d+\s+\d+/\d+|\d+/\d+|\d+(?:\.\d+)?)"#
    static let rangeSep = #"(?:–|—|-|\s+to\s+)"#
    /// Any Unicode letter. The old `[A-Za-zÀ-ÿ]` excluded ă, ș and ț, so every Romanian
    /// line fell through to amount 0.
    static let word = #"[^\W\d_]+"#
    /// Zero-width assertion for "not inside a word", used as look-around.
    private static let notWord = #"[^\W\d_]"#

    // MARK: - Text helpers

    /// Romanian dictation emits the legacy cedilla forms about as often as the correct
    /// comma-below ones; fold them together before anything else looks at the string.
    private static let cedillaFix: [Character: Character] = [
        "ş": "ș", "Ş": "Ș", "ţ": "ț", "Ţ": "Ț",
    ]

    private static let vulgar: [(String, String)] = [
        ("¼", "1/4"), ("½", "1/2"), ("¾", "3/4"),
        ("⅐", "1/7"), ("⅑", "1/9"), ("⅒", "1/10"),
        ("⅓", "1/3"), ("⅔", "2/3"),
        ("⅕", "1/5"), ("⅖", "2/5"), ("⅗", "3/5"), ("⅘", "4/5"),
        ("⅙", "1/6"), ("⅚", "5/6"),
        ("⅛", "1/8"), ("⅜", "3/8"), ("⅝", "5/8"), ("⅞", "7/8"),
    ]

    /// "Vișinată" → "Visinata". ß → ss (NFKD leaves it alone).
    ///
    /// Note this folds *harder* than `TextFold.stripDiacritics`, which the shopping list
    /// uses: the cedilla map and the ß expansion are parsing-specific. The two are
    /// genuinely different functions in the Python too; keeping them separate is
    /// deliberate, and both are fixture-pinned.
    static func stripDiacritics(_ text: String) -> String {
        var mapped = String(text.map { cedillaFix[$0] ?? $0 })
        mapped = mapped.replacingOccurrences(of: "ß", with: "ss")
                       .replacingOccurrences(of: "ẞ", with: "SS")
        return TextFold.stripDiacritics(mapped)
    }

    /// A phrase and its de-accented twin, so dictation that drops diacritics still matches.
    private static func variants(_ phrase: String) -> [String] {
        let bare = stripDiacritics(phrase)
        return bare == phrase ? [phrase] : [phrase, bare]
    }

    /// Regex alternation over phrases, longest first so "cuillère à soupe" beats "cuillère".
    ///
    /// Python's `sort` is stable and its dicts iterate in insertion order, which is why
    /// every table feeding this is an *ordered array* here rather than a Swift
    /// `Dictionary` — dictionary order is unspecified, and a nondeterministic alternation
    /// would make the parser's behaviour depend on hash seeding.
    private static func alternation(_ phrases: [String]) -> String {
        var out: [String] = []
        for p in phrases { out.append(contentsOf: variants(p)) }
        return out.enumerated()
            .sorted { $0.element.count != $1.element.count
                        ? $0.element.count > $1.element.count
                        : $0.offset < $1.offset }
            .map { $0.element.split(separator: " ")
                    .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    .joined(separator: #"\s+"#) }
            .joined(separator: "|")
    }

    // MARK: - Lexicon

    struct Lexicon {
        /// Spoken unit phrase → a key of `unitMap`. Ordered.
        var units: [(String, String)] = []
        /// Spoken number phrase → value, matched only at the start of a line. Ordered.
        var numbers: [(String, Double)] = []
        /// "N and a half" suffixes → the value they add. Ordered.
        var halfSuffixes: [(String, Double)] = []
        var pinch: [String] = []
        var toTaste: [String] = []
        /// Partitive glue between unit and name — "200 g **de** farine".
        var connectors: [String] = []
        var approx: [String] = []
        /// True where "1,5" means one and a half.
        var decimalComma = false
        var categories: [(String, String)] = []
    }

    /// Expand "<n> <fraction phrase>" into the number table.
    ///
    /// Recipes are full of these — "two and a quarter cups flour", "deux et demi tasses".
    /// Without the expansion the fraction is left stranded in the ingredient *name* and
    /// the amount is silently wrong.
    private static func ones(_ pairs: [(String, Double)],
                             _ fractionSuffixes: [(String, Double)]) -> [(String, Double)] {
        var out = pairs
        for (word, value) in pairs where value == value.rounded() && value >= 1 {
            for (phrase, extra) in fractionSuffixes {
                out.append(("\(word) \(phrase)", value + extra))
            }
        }
        return out
    }

    private static let third = 1.0 / 3.0
    private static let twoThirds = 2.0 / 3.0

    private static let enOnes: [(String, Double)] = [
        ("one", 1), ("two", 2), ("three", 3), ("four", 4), ("five", 5), ("six", 6),
        ("seven", 7), ("eight", 8), ("nine", 9), ("ten", 10), ("eleven", 11),
        ("twelve", 12), ("fifteen", 15), ("twenty", 20),
    ]
    private static let frOnes: [(String, Double)] = [
        ("un", 1), ("une", 1), ("deux", 2), ("trois", 3), ("quatre", 4), ("cinq", 5),
        ("six", 6), ("sept", 7), ("huit", 8), ("neuf", 9), ("dix", 10), ("douze", 12),
        ("quinze", 15), ("vingt", 20),
    ]
    private static let deOnes: [(String, Double)] = [
        ("ein", 1), ("eine", 1), ("einen", 1), ("zwei", 2), ("drei", 3), ("vier", 4),
        ("fünf", 5), ("sechs", 6), ("sieben", 7), ("acht", 8), ("neun", 9), ("zehn", 10),
        ("zwölf", 12), ("fünfzehn", 15), ("zwanzig", 20),
    ]
    private static let roOnes: [(String, Double)] = [
        ("un", 1), ("o", 1), ("doi", 2), ("două", 2), ("trei", 3), ("patru", 4),
        ("cinci", 5), ("șase", 6), ("șapte", 7), ("opt", 8), ("nouă", 9), ("zece", 10),
        ("doisprezece", 12), ("cincisprezece", 15), ("douăzeci", 20),
    ]

    static let categoryOrder = [
        "Sauces & Salsas", "Marinades", "Salads", "Soups & Stews", "Sandwiches",
        "Pasta", "Entrées", "Sides", "Breakfast", "Baking & Desserts",
        "Drinks", "Appetizers & Preserves", "Reference",
    ]

    static let lexicons: [String: Lexicon] = [
        "en": Lexicon(
            units: [
                ("tablespoons", "tbsp"), ("tablespoon", "tbsp"),
                ("teaspoons", "tsp"), ("teaspoon", "tsp"),
                ("cups", "cup"), ("cup", "cup"),
                ("pounds", "lb"), ("pound", "lb"),
                ("ounces", "oz"), ("ounce", "oz"),
                ("grams", "g"), ("gram", "g"),
                ("kilograms", "kg"), ("kilogram", "kg"), ("kilos", "kg"), ("kilo", "kg"),
                ("millilitres", "ml"), ("milliliters", "ml"),
                ("millilitre", "ml"), ("milliliter", "ml"),
                ("litres", "l"), ("liters", "l"), ("litre", "l"), ("liter", "l"),
            ],
            numbers: ones(enOnes, [("and a half", 0.5), ("and a quarter", 0.25),
                                   ("and three quarters", 0.75), ("and a third", third),
                                   ("and two thirds", twoThirds)])
                + [("half a", 0.5), ("a half", 0.5), ("half", 0.5),
                   ("a quarter of a", 0.25), ("a quarter", 0.25), ("quarter", 0.25),
                   ("three quarters of a", 0.75), ("three quarters", 0.75),
                   ("a third of a", third), ("a third", third), ("two thirds", twoThirds),
                   ("a", 1), ("an", 1)],
            halfSuffixes: [("and a half", 0.5), ("and a quarter", 0.25),
                           ("and three quarters", 0.75), ("and a third", third)],
            pinch: ["a pinch of", "a pinch", "pinch of", "a dash of", "a dash"],
            toTaste: ["to taste", "season to taste"],
            connectors: ["of"],
            approx: ["about", "roughly", "around", "approximately"]
        ),
        "fr": Lexicon(
            units: [
                ("cuillères à soupe", "tbsp"), ("cuillère à soupe", "tbsp"),
                ("cuillères à table", "tbsp"), ("cuillère à table", "tbsp"),
                ("c. à s.", "tbsp"), ("c à s", "tbsp"), ("cas", "tbsp"),
                ("cuillères à café", "tsp"), ("cuillère à café", "tsp"),
                ("cuillères à thé", "tsp"), ("cuillère à thé", "tsp"),
                ("c. à c.", "tsp"), ("c à c", "tsp"), ("cac", "tsp"),
                ("tasses", "cup"), ("tasse", "cup"),
                ("grammes", "g"), ("gramme", "g"),
                ("kilogrammes", "kg"), ("kilogramme", "kg"), ("kilos", "kg"), ("kilo", "kg"),
                ("millilitres", "ml"), ("millilitre", "ml"),
                ("litres", "l"), ("litre", "l"),
                // A French *livre* is 500 g, not a pound.
                ("livres", "halfkilo"), ("livre", "halfkilo"),
            ],
            numbers: ones(frOnes, [("et demi", 0.5), ("et demie", 0.5),
                                   ("et quart", 0.25), ("et un quart", 0.25)])
                + [("un demi", 0.5), ("une demie", 0.5), ("demi", 0.5), ("demie", 0.5),
                   ("un quart de", 0.25), ("un quart", 0.25), ("quart", 0.25),
                   ("trois quarts de", 0.75), ("trois quarts", 0.75),
                   ("un tiers de", third), ("un tiers", third), ("deux tiers", twoThirds)],
            halfSuffixes: [("et demi", 0.5), ("et demie", 0.5),
                           ("et quart", 0.25), ("et un quart", 0.25)],
            pinch: ["une pincée de", "une pincée", "pincée de", "pincée"],
            toTaste: ["à votre goût", "selon le goût", "selon votre goût", "au goût"],
            connectors: ["de la", "de l'", "des", "du", "d'", "de"],
            approx: ["environ", "à peu près"],
            decimalComma: true,
            categories: [
                ("sauces", "Sauces & Salsas"), ("sauce", "Sauces & Salsas"),
                ("marinades", "Marinades"), ("marinade", "Marinades"),
                ("salades", "Salads"), ("salade", "Salads"),
                ("soupes", "Soups & Stews"), ("soupe", "Soups & Stews"),
                ("potages", "Soups & Stews"),
                ("sandwichs", "Sandwiches"), ("sandwich", "Sandwiches"),
                ("pâtes", "Pasta"),
                // Careful: French *entrée* is a starter. The English category "Entrées"
                // is the main course, so these two must not be matched to each other.
                ("plats principaux", "Entrées"), ("plat principal", "Entrées"),
                ("plats", "Entrées"),
                ("accompagnements", "Sides"), ("accompagnement", "Sides"),
                ("garnitures", "Sides"),
                ("petit-déjeuner", "Breakfast"), ("petit déjeuner", "Breakfast"),
                ("desserts", "Baking & Desserts"), ("dessert", "Baking & Desserts"),
                ("pâtisserie", "Baking & Desserts"), ("boulangerie", "Baking & Desserts"),
                ("boissons", "Drinks"), ("boisson", "Drinks"),
                ("entrées", "Appetizers & Preserves"), ("entrée", "Appetizers & Preserves"),
                ("apéritifs", "Appetizers & Preserves"),
                ("conserves", "Appetizers & Preserves"),
                ("référence", "Reference"),
            ]
        ),
        "de": Lexicon(
            units: [
                ("esslöffel", "tbsp"), ("suppenlöffel", "tbsp"), ("el", "tbsp"),
                ("essl.", "tbsp"),
                ("teelöffel", "tsp"), ("kaffeelöffel", "tsp"), ("tl", "tsp"), ("teel.", "tsp"),
                ("tassen", "cup"), ("tasse", "cup"), ("becher", "cup"),
                ("gramm", "g"),
                ("kilogramm", "kg"), ("kilo", "kg"),
                ("milliliter", "ml"),
                ("liter", "l"),
                // A German *Pfund* is 500 g, not a pound.
                ("pfund", "halfkilo"),
            ],
            numbers: deOnes
                + [("anderthalb", 1.5), ("eineinhalb", 1.5), ("zweieinhalb", 2.5),
                   ("dreieinhalb", 3.5), ("viereinhalb", 4.5), ("fünfeinhalb", 5.5),
                   ("ein halber", 0.5), ("eine halbe", 0.5), ("ein halbes", 0.5),
                   ("halb", 0.5),
                   ("ein viertel", 0.25), ("viertel", 0.25),
                   ("dreiviertel", 0.75), ("drei viertel", 0.75),
                   ("ein drittel", third), ("zwei drittel", twoThirds)],
            pinch: ["eine prise", "prise", "eine messerspitze", "messerspitze"],
            toTaste: ["nach geschmack", "nach belieben"],
            approx: ["etwa", "ca.", "circa", "ungefähr"],
            decimalComma: true,
            categories: [
                ("saucen", "Sauces & Salsas"), ("soßen", "Sauces & Salsas"),
                ("sauce", "Sauces & Salsas"),
                ("marinaden", "Marinades"), ("marinade", "Marinades"),
                ("salate", "Salads"), ("salat", "Salads"),
                ("suppen", "Soups & Stews"), ("suppe", "Soups & Stews"),
                ("eintöpfe", "Soups & Stews"),
                ("sandwiches", "Sandwiches"), ("brote", "Sandwiches"),
                ("nudeln", "Pasta"), ("pasta", "Pasta"),
                ("hauptgerichte", "Entrées"), ("hauptgericht", "Entrées"),
                ("hauptspeisen", "Entrées"),
                ("beilagen", "Sides"), ("beilage", "Sides"),
                ("frühstück", "Breakfast"),
                ("backen", "Baking & Desserts"), ("desserts", "Baking & Desserts"),
                ("nachspeisen", "Baking & Desserts"), ("kuchen", "Baking & Desserts"),
                ("getränke", "Drinks"),
                ("vorspeisen", "Appetizers & Preserves"),
                ("vorspeise", "Appetizers & Preserves"),
                ("eingemachtes", "Appetizers & Preserves"),
                ("referenz", "Reference"),
            ]
        ),
        "ro": Lexicon(
            units: [
                ("linguri", "tbsp"), ("lingură", "tbsp"),
                ("lingurițe", "tsp"), ("linguriță", "tsp"),
                ("căni", "cup"), ("cană", "cup"),
                ("grame", "g"), ("gram", "g"),
                ("kilograme", "kg"), ("kilogram", "kg"), ("kile", "kg"), ("kil", "kg"),
                ("mililitri", "ml"), ("mililitru", "ml"),
                ("litri", "l"), ("litru", "l"),
            ],
            numbers: ones(roOnes, [("și jumătate", 0.5), ("si jumatate", 0.5),
                                   ("și un sfert", 0.25)])
                + [("o jumătate de", 0.5), ("o jumătate", 0.5),
                   ("jumătate de", 0.5), ("jumătate", 0.5),
                   ("un sfert de", 0.25), ("un sfert", 0.25), ("sfert", 0.25),
                   ("trei sferturi de", 0.75), ("trei sferturi", 0.75),
                   ("o treime de", third), ("o treime", third), ("două treimi", twoThirds)],
            halfSuffixes: [("și jumătate", 0.5), ("si jumatate", 0.5), ("și un sfert", 0.25)],
            pinch: ["un praf de", "un praf", "praf de", "un vârf de cuțit de",
                    "un vârf de cuțit", "vârf de cuțit"],
            toTaste: ["după gust", "dupa gust"],
            connectors: ["de"],
            approx: ["aproximativ", "cam", "circa"],
            decimalComma: true,
            categories: [
                ("sosuri", "Sauces & Salsas"), ("sos", "Sauces & Salsas"),
                ("marinate", "Marinades"), ("marinadă", "Marinades"),
                ("salate", "Salads"), ("salată", "Salads"),
                ("supe", "Soups & Stews"), ("supă", "Soups & Stews"),
                ("ciorbe", "Soups & Stews"), ("ciorbă", "Soups & Stews"),
                ("tocănițe", "Soups & Stews"),
                ("sandvișuri", "Sandwiches"), ("sandviș", "Sandwiches"),
                ("paste", "Pasta"),
                ("feluri principale", "Entrées"), ("fel principal", "Entrées"),
                ("principale", "Entrées"),
                ("garnituri", "Sides"), ("garnitură", "Sides"),
                ("mic dejun", "Breakfast"),
                ("deserturi", "Baking & Desserts"), ("desert", "Baking & Desserts"),
                ("prăjituri", "Baking & Desserts"), ("cozonaci", "Baking & Desserts"),
                ("băuturi", "Drinks"), ("băutură", "Drinks"),
                ("aperitive", "Appetizers & Preserves"),
                ("aperitiv", "Appetizers & Preserves"),
                ("conserve", "Appetizers & Preserves"),
                ("murături", "Appetizers & Preserves"),
                ("referință", "Reference"),
            ]
        ),
    ]

    static func lexicon(_ lang: String) -> Lexicon { lexicons[lang] ?? lexicons["en"]! }

    // MARK: - Compiled per language

    private struct Compiled {
        let lex: Lexicon
        let units: Regex
        let unitLookup: [String: String]
        let numbers: Regex
        let numberLookup: [String: Double]
        let halves: Regex?
        let halfLookup: [String: Double]
        let pinch: Regex?
        let toTaste: Regex?
        let connectors: Regex?
        let approx: Regex?
    }

    private static func compile(_ lang: String) -> Compiled {
        let lex = lexicon(lang)

        func lookup<T>(_ pairs: [(String, T)]) -> [String: T] {
            var out: [String: T] = [:]
            for (phrase, value) in pairs {
                for variant in variants(phrase) {
                    out[variant.lowercased().replacingOccurrences(
                        of: #"\s+"#, with: " ", options: .regularExpression)] = value
                }
            }
            return out
        }

        let unitPhrases = lex.units.map(\.0)
        let units = Regex("(?<!\(notWord))(\(alternation(unitPhrases)))(?!\(notWord))")

        let numberPhrases = lex.numbers.map(\.0)
        let numbers = Regex("^\\s*(\(alternation(numberPhrases)))(?!\(notWord))")

        // "2 and a half cups", but also "a cup and a half" — English, French and Romanian
        // all let the fraction follow the unit. Units are already canonical by the time
        // this runs, so the optional middle group matches unitMap's *values*.
        let canonicalUnits = Set(unitMap.values).sorted { $0.count != $1.count
            ? $0.count > $1.count : $0 < $1 }
            .map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let halves: Regex? = lex.halfSuffixes.isEmpty ? nil : Regex(
            "^\\s*(\(num))\\s+(?:(\(canonicalUnits))\\s+)?(\(alternation(lex.halfSuffixes.map(\.0))))(?!\(notWord))")

        let pinch: Regex? = lex.pinch.isEmpty ? nil
            : Regex("(?<!\(notWord))(?:\(alternation(lex.pinch)))(?!\(notWord))\\s*")
        let toTaste: Regex? = lex.toTaste.isEmpty ? nil
            : Regex("[,;]?\\s*(?<!\(notWord))(?:\(alternation(lex.toTaste)))(?!\(notWord))\\s*")

        // Strip the partitive glue between a unit and the name: "200 g de farine" →
        // "200 g farine". The trailing boundary must tolerate elision — French "d'huile"
        // has no space after "d'".
        let connectors: Regex? = lex.connectors.isEmpty ? nil : Regex(
            "(?<=\\s)(\(canonicalUnits))\\s+(?:\(alternation(lex.connectors)))(?:(?<=')|(?!\(notWord)))\\s*")

        let approx: Regex? = lex.approx.isEmpty ? nil
            : Regex("(?<!\(notWord))(?:\(alternation(lex.approx)))(?!\(notWord))\\s*")

        return Compiled(lex: lex, units: units, unitLookup: lookup(lex.units),
                        numbers: numbers, numberLookup: lookup(lex.numbers),
                        halves: halves, halfLookup: lookup(lex.halfSuffixes),
                        pinch: pinch, toTaste: toTaste, connectors: connectors,
                        approx: approx)
    }

    private static let compiled: [String: Compiled] = {
        var out: [String: Compiled] = [:]
        for lang in ["en", "fr", "de", "ro"] { out[lang] = compile(lang) }
        return out
    }()

    private static func comp(_ lang: String) -> Compiled { compiled[lang] ?? compiled["en"]! }

    // MARK: - Spoken pre-pass

    /// Rewrite a dictated line into the English-canonical form the core parser reads.
    ///
    ///     "zweieinhalb Esslöffel Paprikapulver" → "2.5 tbsp Paprikapulver"
    ///     "200 grammes de farine"               → "200 g farine"
    ///     "1,5 kg de roșii"                     → "1.5 kg roșii"
    ///
    /// Ingredient names are never touched beyond the glue words in front of them.
    static func normaliseSpoken(_ text: String, lang: String = "en") -> String {
        let c = comp(lang)
        var text = text.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        text = String(text.map { cedillaFix[$0] ?? $0 })

        // ¾ → 3/4, and 1½ → 1 1/2
        for (glyph, asciiForm) in vulgar {
            text = Regex("(?<=\\d)\\s*\(NSRegularExpression.escapedPattern(for: glyph))")
                .replacingAll(in: text, with: " \(asciiForm)")
            text = text.replacingOccurrences(of: glyph, with: asciiForm)
        }

        if c.lex.decimalComma {
            text = Regex(#"(?<=\d),(?=\d)"#).replacingAll(in: text, with: ".")
        }

        if let approx = c.approx {
            text = approx.replacingFirst(in: text, with: "~")
        }

        // Unit phrases → canonical abbreviations, before number words so that
        // "un quart de tasse" still finds its unit.
        text = c.units.replacingAll(in: text) { groups in
            let key = (groups[1] ?? "").lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            return c.unitLookup[key] ?? groups[1] ?? ""
        }

        // Leading number phrase → digits. Only at the start: an ingredient line is
        // "<quantity> <unit> <name>", and substituting mid-string would mangle names.
        if let m = c.numbers.firstMatch(in: text) {
            let key = (m.groups[1] ?? "").lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            if let value = c.numberLookup[key] {
                let rest = String(text[m.range.upperBound...])
                    .drop(while: { $0 == " " || $0 == "\t" })
                text = "\(fmt(value)) \(rest)".trimmingCharacters(in: .whitespaces)
            }
        }

        // "2 et demi" / "2 și jumătate", and the unit-in-the-middle word order:
        // "1 cup and a half" / "o cană și jumătate" / "une tasse et demie".
        if let halves = c.halves, let m = halves.firstMatch(in: text) {
            let key = (m.groups[3] ?? "").lowercased()
                .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            let extra = c.halfLookup[key] ?? 0.5
            let unit = m.groups[2].map { "\($0) " } ?? ""
            let rest = String(text[m.range.upperBound...]).drop(while: { $0 == " " || $0 == "\t" })
            text = "\(fmt(numeric(m.groups[1] ?? "0") + extra)) \(unit)\(rest)"
                .trimmingCharacters(in: .whitespaces)
        }

        // Partitive glue between the unit and the name: "200 g de farine" → "200 g farine".
        if let connectors = c.connectors {
            text = connectors.replacingFirst(in: text, withTemplate: "$1 ")
        }

        return Regex(#"\s{2,}"#).replacingAll(in: text, with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func fmt(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : shortestDecimal(value)
    }

    /// Python's `f"{value:g}"` — up to 6 significant digits, trailing zeros dropped.
    private static func shortestDecimal(_ value: Double) -> String {
        var s = String(format: "%g", value)
        if s.contains("e") { s = String(format: "%.6g", value) }
        return s
    }

    // MARK: - Core parser

    private static func numeric(_ token: String) -> Double {
        let token = token.trimmingCharacters(in: .whitespaces)
        if let m = Regex(#"^(\d+)\s+(\d+)/(\d+)$"#).firstMatch(in: token),
           let whole = Double(m.groups[1] ?? ""), let n = Double(m.groups[2] ?? ""),
           let d = Double(m.groups[3] ?? ""), d != 0 {
            return whole + n / d
        }
        if token.contains("/") {
            let parts = token.split(separator: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 {
                return n / d
            }
        }
        return Double(token) ?? 0
    }

    private static func normUnit(_ word: String) -> String? {
        unitMap[word.lowercased().replacingOccurrences(
            of: #"\.+$"#, with: "", options: .regularExpression)]
    }

    private static func convert(_ amount: Double, _ unit: String?) -> (Double, String) {
        if let unit, let (base, factor) = metricFactor[unit] { return (amount * factor, base) }
        return (amount, unit ?? "")
    }

    /// One ingredient line → `Ingredient`. amount 0 = to taste.
    ///
    /// `spoken` runs the dictation pre-pass and applies the pinch/to-taste rule. The
    /// default is the printed-text behaviour the seed importer depends on.
    static func parse(_ line: String, section: String? = nil,
                      lang: String = "en", spoken: Bool = false) -> Ingredient {
        var text = line.trimmingCharacters(in: .whitespaces)
        while text.hasPrefix("-") { text.removeFirst() }
        text = text.trimmingCharacters(in: .whitespaces)

        var forcedZero = false
        if spoken {
            let c = comp(lang)
            // Detect the markers on the raw text, before unit rewriting can eat "pincée".
            if let pinch = c.pinch, pinch.firstMatch(in: text) != nil {
                text = pinch.replacingFirst(in: text, with: "")
                forcedZero = true
            }
            if let toTaste = c.toTaste, toTaste.firstMatch(in: text) != nil {
                text = toTaste.replacingAll(in: text, with: " ")
                    .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
                forcedZero = true
            }
            text = normaliseSpoken(text, lang: lang)
        }

        var amount = 0.0
        var unit = ""
        var name = text

        if let juice = Regex("(?:Juice|Zest) of (~?\(num))(?:\(rangeSep)(~?\(num)))?\\s+(.+)")
            .firstMatch(in: text) {
            let lo = numeric((juice.groups[1] ?? "").replacingOccurrences(of: "~", with: ""))
            let hi = juice.groups[2].map { numeric($0.replacingOccurrences(of: "~", with: "")) } ?? lo
            let verb = text.lowercased().hasPrefix("juice") ? "juiced" : "zested"
            amount = (lo + hi) / 2
            unit = ""
            name = "\((juice.groups[3] ?? "").trimmedTrailing(",")), \(verb)"
        } else if let m = Regex("~?(\(num))\\s*(\(word))?\\.?\\s*(?:\(rangeSep)\\s*~?(\(num))\\s*(\(word))?\\.?)?\\s+(.*)")
            .firstMatch(in: text) {
            let loRaw = m.groups[1] ?? ""
            let u1Raw = m.groups[2]
            let hiRaw = m.groups[3]
            let u2Raw = m.groups[4]
            let rest = m.groups[5] ?? ""
            let u1 = u1Raw.flatMap(normUnit)
            let u2 = u2Raw.flatMap(normUnit)

            if let hiRaw {
                // true range; each side may carry its own unit ("700 g–1 kg")
                let (lo, _) = convert(numeric(loRaw), u1 ?? u2)
                let (hi, unitOut) = convert(numeric(hiRaw), u2 ?? u1)
                var n = rest.trimmingCharacters(in: .whitespaces)
                if u2 == nil, let u2Raw { n = "\(u2Raw) \(n)" }
                amount = (lo + hi) / 2
                unit = (u1 ?? u2) != nil ? unitOut : ""
                name = n
            } else {
                let (a, unitOut) = convert(numeric(loRaw), u1)
                var n = rest.trimmingCharacters(in: .whitespaces)
                if u1 == nil, let u1Raw {
                    // not a unit word — it's part of the name ("1 can diced tomatoes")
                    n = "\(u1Raw) \(n)"
                }
                amount = a
                unit = u1 != nil ? unitOut : ""
                name = n
            }
        } else if let m = Regex("~?(\(num))\\s*\(rangeSep)\\s*~?(\(num))\\s*(\(word))?\\.?\\s+(.*)")
            .firstMatch(in: text) {
            // ranges like "1.5–2 lb" — normalise both sides
            let lo = numeric(m.groups[1] ?? ""), hi = numeric(m.groups[2] ?? "")
            let u = (m.groups[3]).flatMap(normUnit)
            let (loC, _) = convert(lo, u)
            let (hiC, unitOut) = convert(hi, u)
            var n = (m.groups[4] ?? "").trimmingCharacters(in: .whitespaces)
            if u == nil, let raw = m.groups[3] { n = "\(raw) \(n)" }
            amount = (loC + hiC) / 2
            unit = u != nil ? unitOut : ""
            name = n
        }

        if forcedZero {
            // "to taste" and "a pinch of" are amount 0 by contract — an em dash that
            // never scales. Never guess a quantity for them (CLAUDE.md §5).
            amount = 0
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
        return Ingredient(amount: amount, unit: unit, name: name, section: section)
    }

    // MARK: - Run-on splitting

    /// Break a punctuation-free dictated run into one ingredient per entry.
    ///
    /// Speech recognition only inserts full stops if the speaker says "period", so a
    /// dictated ingredient list usually arrives as one long string:
    ///
    ///     "two pounds beef chuck three onions four cloves of garlic"
    ///
    /// Splitting on punctuation yields one ingredient — the reported bug, verbatim: *"I
    /// dictated the entire recipe and it added it as one ingredient."* Quantities are the
    /// reliable boundary instead, in whichever language.
    ///
    /// Guards against cutting inside a quantity: mixed fractions ("1 1/2 cups"), ranges
    /// ("2 to 3 cloves"), and a number that is part of the name ("1-inch cubes", "2 cm
    /// dice") all stay whole.
    static func splitRunOn(_ line: String, lang: String = "en") -> [String] {
        let text = Regex(#"\s+"#).replacingAll(
            in: line.trimmingCharacters(in: .whitespacesAndNewlines), with: " ")
        if text.isEmpty { return [] }

        let lex = lexicon(lang)
        let numberWords = Set(lex.numbers.compactMap { $0.0.split(separator: " ").first
            .map(String.init) })
        var connectors = Set(lex.connectors.map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: " '")) })
        connectors.formUnion(["to", "or", "and"])

        let tokens = text.split(separator: " ").map(String.init)
        let isNumber = Regex(#"^~?\d+(?:[.,]\d+)?(?:/\d+)?$"#)
        let isPlainNumber = Regex(#"^~?\d+(?:[.,]\d+)?$"#)
        let isDimension = Regex(#"^(inch|cm|mm|inches|centimet)"#)

        var starts = [0]
        for i in 1..<max(tokens.count, 1) {
            let tok = tokens[i].lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            let prev = tokens[i - 1].lowercased()
                .trimmingCharacters(in: CharacterSet(charactersIn: ",;"))

            guard isNumber.firstMatch(in: tok)?.matchedWhole == true || numberWords.contains(tok)
            else { continue }
            // Second half of a mixed fraction, a range, or a hyphenated measurement.
            if isPlainNumber.firstMatch(in: prev)?.matchedWhole == true
                || connectors.contains(prev) || numberWords.contains(prev) { continue }
            // A number gluing onto the previous word ("1-inch", "2 cm") is part of a name.
            if i + 1 < tokens.count,
               isDimension.firstMatch(in: tokens[i + 1].lowercased()) != nil { continue }
            // Do not cut so soon that the previous piece has no name in it.
            if i - (starts.last ?? 0) < 2 { continue }
            starts.append(i)
        }

        if starts.count < 2 { return [text] }

        var pieces: [String] = []
        let bounds = zip(starts, starts.dropFirst() + [tokens.count])
        for (a, b) in bounds {
            let piece = tokens[a..<b].joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            if !piece.isEmpty { pieces.append(piece) }
        }
        return pieces
    }

    /// Parse a dictated block, skipping blank lines.
    ///
    /// When spoken, a line carrying several quantities is a run of ingredients the speech
    /// recogniser never punctuated — split it rather than storing the lot as one
    /// ingredient named after the whole sentence.
    static func parseLines(_ lines: [String], lang: String = "en",
                           spoken: Bool = true) -> [Ingredient] {
        var out: [Ingredient] = []
        for line in lines where !line.trimmingCharacters(in: .whitespaces).isEmpty {
            let parts = spoken ? splitRunOn(line, lang: lang) : [line]
            out.append(contentsOf: parts.map { parse($0, lang: lang, spoken: spoken) })
        }
        return out
    }

    // MARK: - Slug

    /// "Vișinată" → "visinata". Matches the API's own `^[a-z0-9][a-z0-9-]*$`.
    ///
    /// Slugs are the QR contract (CLAUDE.md §5) — generated once, never renamed.
    static func slugify(_ title: String) -> String {
        var slug = stripDiacritics(title).lowercased()
        slug = Regex("[^a-z0-9]+").replacingAll(in: slug, with: "-")
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return Regex("-{2,}").replacingAll(in: slug, with: "-")
    }

    static func isValidSlug(_ slug: String) -> Bool {
        Regex("^[a-z0-9][a-z0-9-]*$", caseInsensitive: false)
            .firstMatch(in: slug)?.matchedWhole == true
    }

    // MARK: - Category

    /// A dictated category name → a `categoryOrder` entry, or nil if nothing matches.
    static func matchCategory(_ spoken: String, lang: String = "en") -> String? {
        let probe = stripDiacritics(spoken).lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: " .,"))
        if probe.isEmpty { return nil }

        for canonical in categoryOrder where stripDiacritics(canonical).lowercased() == probe {
            return canonical
        }

        var tables = [lexicon(lang).categories]
        for key in ["en", "fr", "de", "ro"] {
            if let l = lexicons[key] { tables.append(l.categories) }
        }
        for table in tables {
            for (phrase, canonical) in table
            where stripDiacritics(phrase).lowercased() == probe {
                return canonical
            }
        }

        // Loose fall-back: the probe is contained in an English category name
        // ("salsa" → "Sauces & Salsas", "dessert" → "Baking & Desserts").
        for canonical in categoryOrder
        where stripDiacritics(canonical).lowercased().contains(probe) {
            return canonical
        }
        return nil
    }
}

private extension String {
    func trimmedTrailing(_ chars: String) -> String {
        var s = self
        while let last = s.last, chars.contains(last) { s.removeLast() }
        return s
    }
}
