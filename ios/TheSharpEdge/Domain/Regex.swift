import Foundation

/// A thin wrapper giving `NSRegularExpression` the shape of Python's `re`.
///
/// `IngredientParse` is a literal port of a regex-dense Python module, and the port is
/// only trustworthy if the primitives line up. The differences that actually bite:
///
/// * Python's `re.match` is anchored at the start but not the end; `NSRegularExpression`
///   is unanchored. `firstMatch(in:)` therefore reports `startsAtBeginning` so callers
///   that need `match` semantics can check it.
/// * Python groups that did not participate are `None`; `NSTextCheckingResult` gives
///   `NSNotFound`. Both surface here as `nil`, never as `""` — the parser genuinely
///   distinguishes "no unit word" from "an empty unit word".
/// * Ranges are `NSRange` over UTF-16. Every accessor converts back to `String.Index`,
///   so accented and Romanian text does not slice mid-character.
///
/// Named `Regex` deliberately shadows nothing in use: the project targets iPadOS 17 with
/// Swift 5, where the stdlib `Regex` type exists but its literal syntax and the
/// `NSRegularExpression` feature set differ; a small explicit wrapper is the boring
/// option and keeps the Python correspondence readable.
struct Regex {

    let pattern: String
    private let re: NSRegularExpression

    /// Patterns here are compile-time constants built from the lexicons. A malformed one
    /// is a programming error, not a runtime condition, so this traps loudly with the
    /// pattern in the message rather than failing silently.
    init(_ pattern: String, caseInsensitive: Bool = true) {
        self.pattern = pattern
        var options: NSRegularExpression.Options = []
        if caseInsensitive { options.insert(.caseInsensitive) }
        do {
            re = try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            preconditionFailure("Bad regex \(pattern): \(error)")
        }
    }

    struct Match {
        /// Group 0 is the whole match; `groups[n]` is nil when group n did not participate.
        let groups: [String?]
        /// Range of the whole match in the searched string.
        let range: Range<String.Index>
        /// True when the match begins at the start of the string (Python `re.match`).
        let startsAtBeginning: Bool
        /// True when the match covers the whole string (Python `re.fullmatch`).
        let matchedWhole: Bool
    }

    func firstMatch(in text: String) -> Match? {
        let full = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: full) else { return nil }
        guard let range = Range(m.range, in: text) else { return nil }

        var groups: [String?] = []
        for i in 0..<m.numberOfRanges {
            if let r = Range(m.range(at: i), in: text) {
                groups.append(String(text[r]))
            } else {
                groups.append(nil)
            }
        }
        return Match(groups: groups,
                     range: range,
                     startsAtBeginning: range.lowerBound == text.startIndex,
                     matchedWhole: range.lowerBound == text.startIndex
                        && range.upperBound == text.endIndex)
    }

    /// Replace every match using a closure over the captured groups (Python's `re.sub`
    /// with a callable).
    func replacingAll(in text: String, with transform: ([String?]) -> String) -> String {
        var result = ""
        var cursor = text.startIndex
        let full = NSRange(text.startIndex..., in: text)

        re.enumerateMatches(in: text, options: [], range: full) { m, _, _ in
            guard let m, let range = Range(m.range, in: text) else { return }
            var groups: [String?] = []
            for i in 0..<m.numberOfRanges {
                groups.append(Range(m.range(at: i), in: text).map { String(text[$0]) })
            }
            result += text[cursor..<range.lowerBound]
            result += transform(groups)
            cursor = range.upperBound
        }
        result += text[cursor...]
        return result
    }

    func replacingAll(in text: String, with replacement: String) -> String {
        replacingAll(in: text) { _ in replacement }
    }

    /// Replace only the first match (Python's `re.sub(..., count=1)`).
    func replacingFirst(in text: String, with replacement: String) -> String {
        guard let m = firstMatch(in: text) else { return text }
        return text.replacingCharacters(in: m.range, with: replacement)
    }

    /// Replace the first match using an `NSRegularExpression` template ("$1").
    func replacingFirst(in text: String, withTemplate template: String) -> String {
        let full = NSRange(text.startIndex..., in: text)
        guard let m = re.firstMatch(in: text, options: [], range: full),
              let range = Range(m.range, in: text) else { return text }
        let replacement = re.replacementString(for: m, in: text, offset: 0, template: template)
        return text.replacingCharacters(in: range, with: replacement)
    }
}
