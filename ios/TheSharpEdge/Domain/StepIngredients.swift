import Foundation

/// Which ingredients a step mentions — the port of `matchIngredients` in
/// `web/src/lib/cook.ts`, with the same stopwords and the same tests. Cook mode
/// uses it to light up the current step's lines in the mise en place.
///
/// Deliberately loose: it only decides what gets highlighted, never an amount,
/// so it is not one of the §14 parity fixtures.
enum StepIngredients {
    static let stopwords: Set<String> = [
        "the", "and", "or", "a", "an", "of", "for", "with", "into", "cut", "plus",
        "fresh", "freshly", "ground", "large", "small", "medium", "ripe", "diced",
        "minced", "chopped", "sliced", "crushed", "grated", "peeled", "seeded",
        "finely", "thinly", "optional", "to", "taste", "more", "divided", "cubed",
        "certified", "gf"
    ]

    /// Significant words from an ingredient name: the part before the first comma,
    /// parentheticals dropped, words of three letters or more.
    static func keywords(_ name: String) -> [String] {
        var core = String(name.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
        core = core.replacingOccurrences(of: #"\(.*?\)"#, with: "", options: .regularExpression)
        return core.lowercased()
            .split(whereSeparator: { !isWordChar($0) })
            .map(String.init)
            .filter { $0.count >= 3 && !stopwords.contains($0) }
    }

    /// Indices of `names` whose keywords appear in `step` as whole words, with
    /// naive plurals stemmed both ways ("onions" ↔ "onion", "potatoes" ↔ "potato").
    static func match(step: String, names: [String]) -> [Int] {
        let text = step.lowercased()
        return names.enumerated().compactMap { index, name in
            let hit = keywords(name).contains { word in
                let base = word.replacingOccurrences(of: #"(es|s)$"#, with: "", options: .regularExpression)
                guard base.count >= 3 else { return false }
                let escaped = NSRegularExpression.escapedPattern(for: base)
                let pattern = "(^|[^a-zà-ÿ])\(escaped)(es|s)?([^a-zà-ÿ]|$)"
                return text.range(of: pattern, options: .regularExpression) != nil
            }
            return hit ? index : nil
        }
    }

    /// Mirrors the web's `[a-zà-ÿ]` class.
    private static func isWordChar(_ c: Character) -> Bool {
        guard let scalar = c.unicodeScalars.first, c.unicodeScalars.count == 1 else { return false }
        return ("a"..."z").contains(scalar) || (0xE0...0xFF).contains(scalar.value)
    }
}
