import Foundation

/// Diacritic folding, matching the Python in `api/app/services/` exactly.
///
/// This exists because the app already folded text three different ways —
/// `.diacriticInsensitive` in one place, folding plus `.caseInsensitive` in another —
/// and neither matched what the server does. Any of those differences moves an
/// ingredient onto the wrong shopping line or into the wrong aisle.
///
/// Python's rule, in both `aisles._fold` and `shopping.normalise_name`:
///
///     "".join(c for c in unicodedata.normalize("NFKD", s) if not unicodedata.combining(c))
///
/// NFKD splits a precomposed letter into base + combining mark, then the marks are
/// dropped: `é` → `e`, `ș` (U+0219) → `s`, `ă` → `a`. Note what it does *not* do — `ß`
/// has no decomposition and survives folding unchanged. That is deliberate parity, not
/// an oversight; see `normaliseName` for what happens to it next.
enum TextFold {

    /// NFKD-decompose and drop combining marks. No case change, no whitespace change.
    static func stripDiacritics(_ text: String) -> String {
        String(text.decomposedStringWithCompatibilityMapping.unicodeScalars.filter {
            !CharacterSet.nonBaseCharacters.contains($0)
        })
    }

    /// `aisles._fold`: strip diacritics, collapse runs of whitespace, trim, lowercase.
    static func fold(_ text: String) -> String {
        collapseWhitespace(stripDiacritics(text)).lowercased()
    }

    /// Python's `re.sub(r"\s+", " ", s).strip()`.
    static func collapseWhitespace(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
