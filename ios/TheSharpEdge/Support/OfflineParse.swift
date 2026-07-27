import Foundation

/// A compact offline stand-in for `api/app/services/ingredients.py`, used only by
/// `SampleDataSource` so the add-recipe and dictation flows are explorable in the
/// simulator with no backend.
///
/// The server is canonical. This covers the common shapes — digits, decimal comma,
/// vulgar fractions, the unit vocabulary of the four capture languages, partitive
/// glue, and the pinch/to-taste rule — and deliberately does not try to be the full
/// lexicon. When the app is pointed at a real backend, `/parse/ingredients` is what
/// actually runs.
enum OfflineParse {

    // Spoken unit phrase → canonical unit, longest first so "cuillère à soupe"
    // beats "cuillère". Values outside ALLOWED_UNITS carry a multiplier to g/ml.
    private static let units: [(String, String, Double)] = [
        // fr
        ("cuillères à soupe", "tbsp", 1), ("cuillère à soupe", "tbsp", 1),
        ("cuillères à café", "tsp", 1), ("cuillère à café", "tsp", 1),
        ("c. à s.", "tbsp", 1), ("c. à c.", "tsp", 1),
        ("grammes", "g", 1), ("gramme", "g", 1),
        ("kilogrammes", "g", 1000), ("kilogramme", "g", 1000), ("kilos", "g", 1000), ("kilo", "g", 1000),
        ("millilitres", "ml", 1), ("millilitre", "ml", 1),
        ("litres", "ml", 1000), ("litre", "ml", 1000),
        ("tasses", "cup", 1), ("tasse", "cup", 1),
        ("livres", "g", 500), ("livre", "g", 500),      // a French livre is 500 g
        // de
        ("esslöffel", "tbsp", 1), ("teelöffel", "tsp", 1),
        ("el", "tbsp", 1), ("tl", "tsp", 1),
        ("gramm", "g", 1), ("kilogramm", "g", 1000),
        ("milliliter", "ml", 1), ("liter", "ml", 1000),
        ("tassen", "cup", 1), ("becher", "cup", 1),
        ("pfund", "g", 500),                            // a German Pfund is 500 g
        // ro
        ("lingurițe", "tsp", 1), ("linguriță", "tsp", 1), ("lingurite", "tsp", 1), ("linguriță", "tsp", 1),
        ("linguri", "tbsp", 1), ("lingură", "tbsp", 1), ("lingura", "tbsp", 1),
        ("grame", "g", 1), ("kilograme", "g", 1000),
        ("mililitri", "ml", 1), ("litri", "ml", 1000), ("litru", "ml", 1000),
        ("căni", "cup", 1), ("cană", "cup", 1), ("cani", "cup", 1), ("cana", "cup", 1),
        // en + shared abbreviations
        ("tablespoons", "tbsp", 1), ("tablespoon", "tbsp", 1),
        ("teaspoons", "tsp", 1), ("teaspoon", "tsp", 1),
        ("kilograms", "g", 1000), ("kilogram", "g", 1000),
        ("millilitres", "ml", 1), ("milliliters", "ml", 1),
        ("litres", "ml", 1000), ("liters", "ml", 1000),
        ("pounds", "lb", 1), ("pound", "lb", 1),
        ("ounces", "oz", 1), ("ounce", "oz", 1),
        ("grams", "g", 1), ("gram", "g", 1),
        ("cups", "cup", 1), ("cup", "cup", 1),
        ("tbsp", "tbsp", 1), ("tsp", "tsp", 1), ("kg", "g", 1000), ("ml", "ml", 1),
        ("lbs", "lb", 1), ("lb", "lb", 1), ("oz", "oz", 1), ("g", "g", 1), ("l", "ml", 1000),
    ]

    private static let numberWords: [String: Double] = [
        "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "half": 0.5,
        "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "demi": 0.5,
        "ein": 1, "eine": 1, "zwei": 2, "drei": 3, "vier": 4, "fünf": 5, "halb": 0.5,
        "anderthalb": 1.5, "eineinhalb": 1.5, "zweieinhalb": 2.5, "dreieinhalb": 3.5,
        "dreiviertel": 0.75,
        "o": 1, "doi": 2, "două": 2, "doua": 2, "trei": 3, "patru": 4, "cinci": 5,
        "jumătate": 0.5, "jumatate": 0.5,
    ]

    private static let pinch = ["a pinch of", "a pinch", "une pincée de", "une pincée", "pincée",
                                "eine prise", "prise", "messerspitze",
                                "un praf de", "un praf", "un vârf de cuțit de", "vârf de cuțit"]
    private static let toTaste = ["to taste", "à votre goût", "au goût", "selon le goût",
                                  "nach geschmack", "nach belieben", "după gust", "dupa gust"]
    private static let connectors = ["de la ", "de l'", "d'", "des ", "du ", "de ", "of "]
    private static let vulgar: [Character: Double] = ["¼": 0.25, "½": 0.5, "¾": 0.75, "⅓": 1.0 / 3, "⅔": 2.0 / 3]

    /// Break a punctuation-free dictated run into one ingredient each. Mirrors
    /// split_run_on() in api/app/services/ingredients.py — without it, sample mode
    /// turns a whole dictated list into a single ingredient even though the server
    /// would have split it correctly.
    static func splitRun(_ raw: String) -> [String] {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let tokens = text.split(separator: " ").map(String.init)
        var starts = [0]

        func isQuantity(_ t: String) -> Bool {
            let k = t.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            if numberWords[k] != nil { return true }
            return Double(k.replacingOccurrences(of: ",", with: ".")) != nil || k.contains("/")
        }
        let glue: Set<String> = ["to", "or", "and", "de", "of", "et", "und"]

        for i in 1..<max(tokens.count, 1) {
            let tok = tokens[i]
            guard isQuantity(tok) else { continue }
            let prev = tokens[i - 1].lowercased()
            // not the second half of "1 1/2" or "2 to 3", and not "1 inch"
            if isQuantity(prev) || glue.contains(prev) { continue }
            if i + 1 < tokens.count,
               ["inch", "inches", "cm", "mm"].contains(tokens[i + 1].lowercased()) { continue }
            if i - starts[starts.count - 1] < 2 { continue }
            starts.append(i)
        }
        guard starts.count > 1 else { return [text] }

        var out: [String] = []
        for (n, a) in starts.enumerated() {
            let b = n + 1 < starts.count ? starts[n + 1] : tokens.count
            let piece = tokens[a..<b].joined(separator: " ")
                .trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))
            if !piece.isEmpty { out.append(piece) }
        }
        return out
    }

    static func ingredient(_ raw: String) -> Ingredient {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        var forcedZero = false

        for marker in pinch where contains(text, marker) {
            text = remove(text, marker); forcedZero = true; break
        }
        for marker in toTaste where contains(text, marker) {
            text = remove(text, marker); forcedZero = true
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))

        var tokens = text.split(separator: " ").map(String.init)
        var amount: Double = 0
        var unit = ""

        // Leading quantity: digits (with a decimal comma), a vulgar fraction, or a number word.
        if let first = tokens.first, let value = number(first) {
            amount = value
            tokens.removeFirst()
            // "2 et demi" / "două și jumătate" / "two and a half"
            if let extra = trailingHalf(&tokens) { amount += extra }
        }

        // Unit: longest phrase match at the head of what's left.
        let rest = tokens.joined(separator: " ")
        for (phrase, canonical, factor) in units.sorted(by: { $0.0.count > $1.0.count }) {
            if startsWithWord(rest, phrase) {
                unit = canonical
                amount *= factor
                tokens = Array(rest.dropFirst(phrase.count)).isEmpty
                    ? []
                    : String(rest.dropFirst(phrase.count)).split(separator: " ").map(String.init)
                break
            }
        }

        var name = tokens.joined(separator: " ")
        for glue in connectors where name.lowercased().hasPrefix(glue) {
            name = String(name.dropFirst(glue.count)); break
        }
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: " ,;"))

        return Ingredient(amount: forcedZero ? 0 : amount, unit: unit, name: name.isEmpty ? raw : name)
    }

    /// Mirrors `slugify()` — strip accents, lowercase, non-alphanumerics become hyphens.
    static func slug(_ title: String) -> String {
        let folded = title
            .replacingOccurrences(of: "ß", with: "ss")
            .folding(options: [.diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .lowercased()
        let parts = folded.split { !$0.isLetter && !$0.isNumber }
        return parts.joined(separator: "-")
    }

    // MARK: - helpers

    private static func number(_ token: String) -> Double? {
        let cleaned = token.replacingOccurrences(of: "~", with: "")
        if let ch = cleaned.first, cleaned.count == 1, let f = vulgar[ch] { return f }
        if let d = Double(cleaned.replacingOccurrences(of: ",", with: ".")) { return d }
        if cleaned.contains("/") {
            let parts = cleaned.split(separator: "/")
            if parts.count == 2, let n = Double(parts[0]), let d = Double(parts[1]), d != 0 { return n / d }
        }
        return numberWords[cleaned.lowercased()]
    }

    /// Consumes "and a half" / "et demi" / "și jumătate" if it leads the remaining tokens.
    private static func trailingHalf(_ tokens: inout [String]) -> Double? {
        let joined = tokens.joined(separator: " ").lowercased()
        for phrase in ["and a half", "et demie", "et demi", "și jumătate", "si jumatate"]
        where joined.hasPrefix(phrase) {
            let remainder = String(joined.dropFirst(phrase.count)).trimmingCharacters(in: .whitespaces)
            // Re-split from the original casing to keep ingredient names intact.
            let dropped = tokens.count - remainder.split(separator: " ").count
            tokens.removeFirst(max(0, dropped))
            return 0.5
        }
        return nil
    }

    private static func contains(_ text: String, _ phrase: String) -> Bool {
        text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static func remove(_ text: String, _ phrase: String) -> String {
        guard let r = text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) else { return text }
        return text.replacingCharacters(in: r, with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func startsWithWord(_ text: String, _ phrase: String) -> Bool {
        guard text.count >= phrase.count,
              text.prefix(phrase.count).compare(phrase, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        else { return false }
        let after = text.dropFirst(phrase.count).first
        return after == nil || after == " "
    }
}
