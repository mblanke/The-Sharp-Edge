import Foundation

/// Merging scaled ingredients into one shopping list.
///
/// A literal port of `api/app/services/shopping.py`, pinned case-for-case by
/// `shared/fixtures/shopping.*.json` (CLAUDE.md §14). In local notebook mode this is
/// the only implementation in the loop, so "the server is canonical" does not apply —
/// this file has to be right on its own.
///
/// The rule that matters: adding a second recipe must **add** to a line, never replace
/// it. Three tbsp of paprika from the goulash plus two from a rub is five tbsp — not
/// two, and not two separate lines. That needs three things, in order:
///
/// 1. **Name normalisation.** Recipe names carry preparation after a comma —
///    "beef chuck, cut into 1-inch cubes". You buy beef chuck.
/// 2. **Unit families.** tsp/tbsp/cup/ml are volume; g/oz/lb are weight; "" is a count.
///    Amounts convert within a family and never across one.
/// 3. **A display unit.** The unit of the *largest single contribution* wins, so the
///    list keeps the cook's own idiom: 1 cup + 2 tbsp reads in cups.
///
/// Amount 0 means "to taste" (CLAUDE.md §5) — those never carry a quantity, because you
/// do not buy "salt, to taste".
enum ShoppingMerge {

    // Everything in a family converts to the family's base unit.
    private static let volume: [String: Double] = ["ml": 1.0, "tsp": 4.92892,
                                                   "tbsp": 14.7868, "cup": 236.588]
    private static let weight: [String: Double] = ["g": 1.0, "oz": 28.3495, "lb": 453.592]
    private static let families: [String: [String: Double]] = ["volume": volume, "weight": weight]

    /// Ingredients that routinely hide gluten. A list that says "check this one" is the
    /// difference between a safe shop and a bad week — CLAUDE.md §1 makes GF
    /// load-bearing, and these are the traps the notebook's reference card names.
    ///
    /// This list previously existed in a shorter, drifted form in `SampleDataSource`
    /// (14 terms against the server's 23). It is now generated-fixture-pinned; do not
    /// edit without adding a case to `shared/fixtures/shopping.check_gluten.json`.
    static let glutenWatch = [
        "paprika", "broth", "stock", "bouillon", "tomato paste", "soy sauce", "tamari",
        "worcestershire", "hoisin", "oyster sauce", "miso", "malt", "vinegar", "mustard",
        "curry powder", "spice blend", "seasoning", "gravy", "sausage", "bacon",
        "imitation crab", "surimi", "oats",
    ]

    /// Food words that end in 's' but are already singular. A suffix rule cannot tell
    /// "molasses" from "limes", so the exceptions are listed rather than guessed at.
    private static let notPlural: Set<String> = [
        "asparagus", "molasses", "couscous", "hummus", "watercress", "cress", "bass",
        "chard", "swiss chard", "brussels", "greens", "grits", "oats", "capers",
    ]

    private static func familyOf(_ unit: String) -> String? {
        for (name, table) in [("volume", volume), ("weight", weight)] where table[unit] != nil {
            return name
        }
        return nil
    }

    /// "Beef chuck, cut into 1-inch cubes" → "beef chuck". The merge key.
    ///
    /// Ported literally, including the deliberately ASCII `[^a-zA-Z0-9 ]` class. Note
    /// this runs *after* diacritic folding, so `é` has already become `e` — but `ß` has
    /// no decomposition and is therefore replaced by a space ("Weißwein" → "wei wein").
    /// That is odd and it is also harmless, because both sides do it identically and the
    /// result is only ever used as a matching key. Do not "improve" it to Unicode
    /// without changing the Python and regenerating the fixtures.
    static func normaliseName(_ name: String) -> String {
        let beforeComma = name.split(separator: ",", maxSplits: 1,
                                     omittingEmptySubsequences: false).first.map(String.init) ?? ""
        var head = TextFold.stripDiacritics(beforeComma)
        head = head.replacingOccurrences(of: #"\([^)]*\)"#, with: " ",
                                         options: .regularExpression)
        head = head.replacingOccurrences(of: "[^a-zA-Z0-9 ]+", with: " ",
                                         options: .regularExpression)
        head = TextFold.collapseWhitespace(head).lowercased()

        // "onions" and "onion" belong on one line. Never turn "asparagus" into "asparagu".
        if head.count > 3, head.hasSuffix("s"), !notPlural.contains(head),
           !head.hasSuffix("ss"), !head.hasSuffix("us"), !head.hasSuffix("is") {
            head.removeLast()
        }
        return head
    }

    /// One line of the list. `amount` is 0 for to-taste items, which never merge.
    struct Line: Equatable {
        var name: String
        var amount: Double = 0
        var unit: String = ""
        var toTaste: Bool = false
        var recipes: [String] = []
        var checked: Bool = false

        var ingredient: String { normaliseName(name) }

        var key: String {
            let family = familyOf(unit) ?? (unit.isEmpty ? "count" : unit)
            return "\(ingredient)|\(toTaste ? "taste" : family)"
        }

        var display: String {
            (toTaste || amount == 0) ? "to taste" : ScalingEngine.formatAmount(amount, unit: unit)
        }

        var checkGluten: Bool {
            let probe = name.lowercased()
            return glutenWatch.contains { probe.contains($0) }
        }

        var aisle: String { Aisles.classify(name) }
    }

    /// Add `extra` into `base`, converting within the unit family.
    private static func mergePair(_ base: inout Line, _ extra: Line) {
        for recipe in extra.recipes where !base.recipes.contains(recipe) {
            base.recipes.append(recipe)
        }

        if base.unit == extra.unit {
            // The common case. Add directly rather than round-tripping through the family
            // base unit, which would turn 2 lb + 1 lb into 2.9999999999999996.
            base.amount += extra.amount
            return
        }

        guard let family = familyOf(base.unit), familyOf(extra.unit) == family,
              let table = families[family] else {
            return  // countables, or units that genuinely do not combine
        }

        let baseInBase = base.amount * (table[base.unit] ?? 0)
        let extraInBase = extra.amount * (table[extra.unit] ?? 0)
        // The larger single contribution decides how the total reads.
        let winnerUnit = baseInBase >= extraInBase ? base.unit : extra.unit
        base.unit = winnerUnit
        base.amount = (baseInBase + extraInBase) / (table[winnerUnit] ?? 1)
    }

    /// Collapse a flat list into one line per ingredient, adding quantities.
    ///
    /// Order is preserved by first appearance, so a list read top to bottom still follows
    /// the order things were added.
    static func merge(_ lines: [Line]) -> [Line] {
        var merged: [String: Line] = [:]
        var order: [String] = []

        for line in lines {
            let key = line.key
            if merged[key] != nil {
                mergePair(&merged[key]!, line)
            } else {
                merged[key] = Line(name: line.name, amount: line.amount, unit: line.unit,
                                   toTaste: line.toTaste || line.amount == 0,
                                   recipes: line.recipes, checked: line.checked)
                order.append(key)
            }
        }

        // A to-taste line for something already being bought by measure is absorbed: one
        // recipe wanting 1 tsp of pepper and another wanting "pepper to taste" means buy
        // pepper, and the measured amount is the more useful of the two. Never the
        // reverse — a measured line is never flattened back to "to taste".
        let measured = Set(order.compactMap { merged[$0]!.toTaste ? nil : merged[$0]!.ingredient })
        let kept = order.filter { !(merged[$0]!.toTaste && measured.contains(merged[$0]!.ingredient)) }
        let keptSet = Set(kept)

        for key in kept where !merged[key]!.toTaste {
            for dropped in order where !keptSet.contains(dropped) {
                guard merged[dropped]!.ingredient == merged[key]!.ingredient else { continue }
                for recipe in merged[dropped]!.recipes where !merged[key]!.recipes.contains(recipe) {
                    merged[key]!.recipes.append(recipe)
                }
            }
        }

        return kept.map { merged[$0]! }
    }

    /// Plain text for the share sheet — AnyList, Notes, Reminders and Messages all take
    /// this. One item per line so list apps split it into separate entries.
    ///
    /// `groupBy` optionally emits an aisle heading before each run, so the pasted list is
    /// walkable rather than a dump. Callers pass the lines already sorted.
    static func asText(_ lines: [Line], title: String = "Shopping list",
                      groupBy: ((Line) -> String)? = nil) -> String {
        var out = [title, ""]
        var current: String?
        for line in lines {
            if let groupBy {
                let heading = groupBy(line)
                if heading != current {
                    if current != nil { out.append("") }
                    out.append(heading)
                    current = heading
                }
            }
            let flag = line.checkGluten ? "  (check GF)" : ""
            out.append("\(line.display) \(line.name)\(flag)")
        }
        return out.joined(separator: "\n")
    }
}
