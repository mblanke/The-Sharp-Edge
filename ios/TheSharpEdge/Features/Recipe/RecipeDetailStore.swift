import SwiftUI

@MainActor
final class RecipeDetailStore: ObservableObject {
    @Published var recipe: RecipeFull?
    @Published var versions: [VersionSummary] = []
    @Published var target: Int = 1
    @Published var isLoading = false
    @Published var error: String?
    @Published var flashing = false
    /// Reading lens for a recipe kept in another language. The stored recipe is
    /// never altered — this only changes what the screen shows.
    @Published var english: RecipeTranslation?
    @Published var readEnglish = false
    @Published var translating = false

    private(set) var slug: String = ""

    var base: Int { recipe?.baseYield ?? 1 }
    var maxYield: Int { max(base, base * 4) }
    var factor: Double { base > 0 ? Double(target) / Double(base) : 1 }

    func load(_ source: DataSource, slug: String) async {
        self.slug = slug
        isLoading = true
        error = nil
        do {
            let full = try await source.recipe(slug)
            recipe = full
            target = full.baseYield
            // versions are best-effort; don't fail the screen if unavailable
            versions = (try? await source.versions(slug)) ?? []
            // a translation may already be cached from an earlier read
            let cached = try? await source.translation(slug, lang: "en")
            english = (cached?.available == true) ? cached : nil
            readEnglish = false
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    /// Words the screen should show, honouring the lens. Amounts never come from
    /// here — they stay the notebook's own.
    /// Keyed by the original name rather than a position: ingredients are grouped
    /// into sections for display, so row order is not the recipe's order.
    private var englishNames: [String: String] {
        guard let originals = recipe?.currentVersion.ingredients,
              let translated = english?.ingredients else { return [:] }
        return Dictionary(zip(originals.map(\.name), translated.map(\.name)),
                          uniquingKeysWith: { first, _ in first })
    }

    func displayName(_ original: String) -> String {
        guard readEnglish else { return original }
        return englishNames[original] ?? original
    }

    func displayStep(_ index: Int, fallback: String) -> String {
        guard readEnglish, let text = english?.steps?[safe: index]?.text else { return fallback }
        return text
    }

    var displayTitle: String {
        (readEnglish ? english?.title : nil) ?? recipe?.title ?? ""
    }

    var displayNotes: [String] {
        (readEnglish ? english?.notes : nil) ?? recipe?.currentVersion.notes ?? []
    }

    /// Translate once and keep it; the API caches per version so later reads are
    /// instant and a later edit invalidates it.
    func translate(_ source: DataSource) async {
        guard !translating else { return }
        translating = true
        defer { translating = false }
        do {
            let made = try await source.makeTranslation(slug, lang: "en")
            if made.available {
                english = made
                readEnglish = true
            }
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Scaled ingredient rows via the client mirror (instant; server /scale is canonical for export).
    var scaledRows: [ScaledRow] {
        guard let recipe else { return [] }
        return ScalingEngine.scale(recipe.currentVersion.ingredients, baseYield: recipe.baseYield, targetYield: target)
    }

    var sections: [Grouping.IngredientSection] { Grouping.sections(scaledRows) }

    func setTarget(_ v: Int) {
        target = min(maxYield, max(1, v))
        flash()
    }

    private var flashTask: Task<Void, Never>?
    func flash() {
        flashing = true
        flashTask?.cancel()
        flashTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            await MainActor.run { self?.flashing = false }
        }
    }

    /// Build a claude.ai deep link embedding the scaled ingredient list (README §61 style).
    func askClaudeURL() -> URL? {
        guard let recipe else { return nil }
        let lines = scaledRows
            .filter { $0.ingredient.amount != 0 || !$0.display.isEmpty }
            .map { row -> String in
                let qty = row.display == ScalingEngine.emDash ? "" : row.display
                return "- \(qty) \(row.name)".trimmingCharacters(in: .whitespaces)
            }
            .joined(separator: "\n")
        let prompt = "I'm cooking \(recipe.title) for \(target) \(recipe.yieldWord). Ingredients:\n\(lines)\nHelp me tweak, substitute, or troubleshoot."
        var comps = URLComponents(string: "https://claude.ai/new")
        comps?.queryItems = [URLQueryItem(name: "q", value: prompt)]
        return comps?.url
    }
}
