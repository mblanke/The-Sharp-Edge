import Foundation

/// Which part of the shop each ingredient comes from.
///
/// A literal port of `api/app/services/aisles.py`, pinned case-for-case by
/// `shared/fixtures/aisles.*.json`. In local notebook mode there is no server to defer
/// to, so this file *is* the classification — see CLAUDE.md §14.
///
/// Deliberately a keyword table rather than anything cleverer: a wrong guess sends you
/// to the wrong end of the shop, and a table is auditable and correctable in one line.
/// Anything unrecognised lands in "Other" rather than being guessed at.
enum Aisles {

    /// Walking order: fresh edges first, then the middle, then frozen last so it spends
    /// least time out of the cold.
    static let order = [
        "Produce",
        "Meat & fish",
        "Dairy & eggs",
        "Bakery",
        "Pantry",
        "Herbs & spices",
        "Frozen",
        "Other",
    ]

    /// Checked before everything else: the cases where two aisles both match and the
    /// shorter word would win by accident. "garlic cloves" is not the spice clove,
    /// "nutmeg" is not a nut, "coconut" is neither.
    private static let overrides: [(String, [String])] = [
        ("Herbs & spices", ["garlic powder", "onion powder", "ground clove", "whole clove",
                            "ground ginger", "nutmeg", "peppercorn"]),
        ("Produce", ["garlic", "spring onion", "green onion", "scallion", "ginger root",
                     "fresh ginger"]),
        ("Pantry", ["coconut", "peanut", "chestnut", "pine nut", "nutella"]),
        ("Produce", ["butternut", "chestnut mushroom"]),
    ]

    private static let rules: [(String, [String])] = [
        // Checked before Dairy/Produce so the specific beats the general.
        ("Pantry", [
            "coconut milk", "coconut cream", "condensed milk", "evaporated milk",
            "almond milk", "oat milk", "soy milk", "buttermilk powder", "peanut butter",
            "tomato paste", "tomato puree", "passata", "canned tomato", "can diced tomato",
            "tomato juice", "spaghetti sauce", "stock", "broth", "bouillon",
            "olive oil", "vegetable oil", "canola", "sesame oil", "oil",
            "vinegar", "soy sauce", "tamari", "worcestershire", "hoisin", "oyster sauce",
            "fish sauce", "mustard", "mayonnaise", "ketchup", "honey", "maple syrup",
            "sugar", "brown sugar", "flour", "cornstarch", "corn starch", "baking soda",
            "baking powder", "yeast", "rice", "pasta", "spaghetti", "noodle", "lentil",
            "chickpea", "bean", "quinoa", "couscous", "oats", "breadcrumb", "panko",
            "chocolate", "cocoa", "vanilla extract", "wine", "bourbon", "tequila",
            "port", "sherry", "stock cube", "gelatin", "cornmeal", "molasses", "capers",
            "olives", "pickle", "jam", "almond", "walnut", "pecan", "cashew",
            "raisin", "dried", "can ", "canned", "tinned", "tin ", "nuts", "mixed nuts",
        ]),
        ("Herbs & spices", [
            "paprika", "cumin", "coriander seed", "caraway", "cinnamon", "nutmeg",
            "cardamom", "turmeric", "curry powder", "chili powder", "chilli powder",
            "cayenne", "peppercorn", "black pepper", "white pepper", "salt", "fleur de sel",
            "bay leaf", "bay leaves", "oregano", "thyme", "rosemary", "sage", "marjoram",
            "tarragon", "dill", "basil", "parsley", "cilantro", "mint", "chive",
            "saffron", "star anise", "fennel seed", "mustard seed", "seasoning", "spice",
            "herbs", "vanilla bean", "ginger, ground", "garlic powder", "onion powder",
        ]),
        ("Meat & fish", [
            "beef", "chuck", "steak", "flank", "brisket", "mince", "ground pork",
            "ground veal", "ground beef", "pork", "bacon", "pancetta", "prosciutto",
            "ham", "sausage", "chicken", "turkey", "duck", "lamb", "veal", "salmon",
            "cod", "haddock", "tuna", "trout", "shrimp", "prawn", "scallop", "oyster",
            "mussel", "clam", "crab", "lobster", "anchovy", "fish", "chorizo",
        ]),
        ("Dairy & eggs", [
            "butter", "milk", "cream", "creme fraiche", "crème fraîche", "sour cream",
            "yogurt", "yoghurt", "cheese", "parmesan", "cheddar", "feta", "mozzarella",
            "gruyere", "gruyère", "comte", "comté", "ricotta", "mascarpone", "egg",
            "buttermilk", "ghee",
        ]),
        ("Bakery", [
            "bread", "baguette", "brioche", "roll", "bun", "tortilla", "pita",
            "croissant", "crouton", "sourdough", "naan", "cake",
        ]),
        ("Frozen", ["frozen", "ice cream", "puff pastry", "filo", "phyllo"]),
        ("Produce", [
            "onion", "shallot", "garlic", "leek", "celery", "carrot", "potato",
            "tomato", "pepper", "cucumber", "lettuce", "spinach", "kale", "chard",
            "cabbage", "broccoli", "cauliflower", "courgette", "zucchini", "aubergine",
            "eggplant", "mushroom", "squash", "pumpkin", "beet", "radish", "turnip",
            "celeriac", "parsnip", "fennel", "asparagus", "green bean", "pea",
            "corn", "avocado", "lemon", "lime", "orange", "apple", "pear", "banana",
            "mango", "pineapple", "watermelon", "melon", "berry", "strawberr",
            "raspberr", "blueberr", "cherry", "cherries", "grape", "peach", "plum",
            "ginger", "chilli", "chili", "jalapeño", "jalapeno", "scallion",
            "green onion", "spring onion", "sprout", "herb",
        ]),
    ]

    /// Longest term first, ties broken by declaration order.
    ///
    /// Python's `sorted(terms, key=len, reverse=True)` is a *stable* sort, so equal-length
    /// terms keep the order they were written in. Swift's `sorted(by:)` is **not** stable,
    /// so the index has to be part of the key — otherwise two same-length terms can swap
    /// and silently change an aisle in a way no obvious test catches.
    private static func termsLongestFirst(_ terms: [String]) -> [String] {
        terms.enumerated()
            .sorted { a, b in
                a.element.count != b.element.count
                    ? a.element.count > b.element.count
                    : a.offset < b.offset
            }
            .map(\.element)
    }

    private static let sortedOverrides: [(String, [String])] =
        overrides.map { ($0.0, termsLongestFirst($0.1)) }
    private static let sortedRules: [(String, [String])] =
        rules.map { ($0.0, termsLongestFirst($0.1)) }

    /// Best-guess aisle for an ingredient name, or "Other" when nothing matches.
    ///
    /// Classified on the part before the first comma, the same head the merge key uses.
    /// Recipe names carry preparation after it — "jalapeño, seeded and minced" — and
    /// preparation is not where a thing lives in the shop. Matching the whole string put
    /// that jalapeño in Meat & fish, because "minced" contains "mince".
    static func classify(_ name: String) -> String {
        let head = TextFold.fold(name.split(separator: ",", maxSplits: 1,
                                            omittingEmptySubsequences: false).first.map(String.init) ?? "")
        let whole = TextFold.fold(name)
        let probe = head.isEmpty ? whole : head
        if probe.isEmpty { return "Other" }

        if let hit = match(probe) { return hit }

        // Nothing in the head — fall back to the whole string before giving up, so
        // "1 can of San Marzano tomatoes, drained" still finds its aisle.
        if probe != whole {
            let flattened = TextFold.fold(name.replacingOccurrences(of: ",", with: " "))
            if let hit = match(flattened) { return hit }
        }
        return "Other"
    }

    private static func match(_ probe: String) -> String? {
        for (aisle, terms) in sortedOverrides where terms.contains(where: probe.contains) {
            return aisle
        }
        for (aisle, terms) in sortedRules where terms.contains(where: probe.contains) {
            return aisle
        }
        return nil
    }

    /// Position in walking order; anything unknown sorts after every named aisle.
    static func rank(_ aisle: String) -> Int {
        order.firstIndex(of: aisle) ?? order.count
    }
}
