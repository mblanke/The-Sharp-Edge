import SwiftUI

/// Renders step text with a bold "Lead-in:" prefix and inline **bold** spans.
/// Mirrors the web boldParts logic: a leading "Verb: " (or "**Lead-in:**") is emphasised.
enum StepText {
    static func attributed(_ text: String) -> AttributedString {
        let working = text
        var result = AttributedString()

        // 1) Explicit markdown-style **bold** spans → try SwiftUI's markdown parser first.
        if working.contains("**"),
           let parsed = try? AttributedString(markdown: working,
                                              options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
            return parsed
        }

        // 2) Implicit lead-in: bold everything up to and including the first colon,
        //    when it reads like a short "Verb phrase:" prefix (<= 6 words before the colon).
        if let colon = working.firstIndex(of: ":") {
            let head = String(working[working.startIndex..<colon])
            let wordCount = head.split(whereSeparator: { $0 == " " }).count
            if wordCount <= 6 && !head.contains(".") {
                var lead = AttributedString(String(working[working.startIndex...colon]))
                lead.font = Typography.body(18, weight: .bold)
                let rest = AttributedString(String(working[working.index(after: colon)...]))
                result.append(lead)
                result.append(rest)
                return result
            }
        }

        return AttributedString(working)
    }
}
