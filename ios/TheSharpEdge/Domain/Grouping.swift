import Foundation

/// Pure grouping/dedup helpers shared across screens.
enum Grouping {
    /// A category with its recipes, in canonical order.
    struct CategorySection: Identifiable {
        var name: String
        var recipes: [RecipeCard]
        var id: String { name }
    }

    /// Group recipe cards by category in canonical (glue-in) order; recipes sorted by title.
    static func byCategory(_ cards: [RecipeCard]) -> [CategorySection] {
        let groups = Dictionary(grouping: cards, by: { $0.category })
        return groups
            .map { CategorySection(name: $0.key, recipes: $0.value.sorted { $0.title < $1.title }) }
            .sorted { (a, b) in
                let ra = Category.rank(a.name), rb = Category.rank(b.name)
                return ra == rb ? a.name < b.name : ra < rb
            }
    }

    /// A named ingredient section, preserving first-appearance order.
    struct IngredientSection: Identifiable {
        var name: String?          // nil = no section header
        var rows: [ScaledRow]
        var id: String { name ?? "—default—" }
    }

    /// Split scaled rows into sections, preserving the order sections first appear.
    static func sections(_ rows: [ScaledRow]) -> [IngredientSection] {
        var order: [String?] = []
        var map: [String: [ScaledRow]] = [:]
        let noKey = "\u{0}nosection"
        for row in rows {
            let key = row.section ?? noKey
            if map[key] == nil {
                map[key] = []
                order.append(row.section)
            }
            map[key]?.append(row)
        }
        return order.map { section in
            IngredientSection(name: section, rows: map[section ?? noKey] ?? [])
        }
    }

    // MARK: Library grouping

    struct BookGroup: Identifiable {
        var book: String
        var hits: [ChunkOut]
        var id: String { book }
    }

    /// Group library hits by book (title), dedup by (book, page), sort by rerank/score desc.
    static func byBook(_ chunks: [ChunkOut]) -> [BookGroup] {
        // Dedup by (title, page) keeping the highest-scoring hit.
        var best: [String: ChunkOut] = [:]
        for c in chunks {
            let key = "\(c.title ?? c.sourcePath ?? "?")|\(c.page ?? -1)"
            let existing = best[key]
            if existing == nil || score(c) > score(existing!) {
                best[key] = c
            }
        }
        let deduped = Array(best.values)
        let groups = Dictionary(grouping: deduped, by: { $0.title ?? $0.sourcePath ?? "Unknown" })
        return groups
            .map { BookGroup(book: $0.key, hits: $0.value.sorted { score($0) > score($1) }) }
            .sorted { bestScore($0.hits) > bestScore($1.hits) }
    }

    private static func score(_ c: ChunkOut) -> Double { c.rerankScore ?? c.score ?? 0 }
    private static func bestScore(_ hits: [ChunkOut]) -> Double { hits.map(score).max() ?? 0 }
}
