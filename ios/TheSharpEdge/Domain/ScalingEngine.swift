import Foundation

/// Kitchen-sane quantity scaling — a verbatim port of api/app/services/scaling.py.
/// The SERVER is canonical (used for shopping list + card export); this mirror drives
/// instant stepper UI. It must match the server bit-for-bit, so:
///   - use half-up floor(x + 0.5), NOT Double.rounded() (banker's) — diverges on exact halves
///   - snap fractions with strict `<` on the error so ties resolve like Python's loop
enum ScalingEngine {
    static let emDash = "—"

    /// (value, glyph) — 0 and 1 anchor the snap; a snapped 1.0 rolls into the whole part.
    static let fractions: [(value: Double, glyph: String)] = [
        (0.0, ""),
        (0.125, "⅛"),
        (0.25, "¼"),
        (1.0 / 3.0, "⅓"),
        (0.375, "⅜"),
        (0.5, "½"),
        (0.625, "⅝"),
        (2.0 / 3.0, "⅔"),
        (0.75, "¾"),
        (0.875, "⅞"),
        (1.0, ""),
    ]

    static let metricUnits: Set<String> = ["g", "ml"]

    /// Half-up rounding: floor(x + 0.5). Matches Python's math.floor(x + 0.5).
    private static func halfUp(_ x: Double) -> Double { (x + 0.5).rounded(.down) }

    /// Render a scaled amount the way a cook would write it.
    static func formatAmount(_ value: Double, unit: String) -> String {
        if value == 0 { return emDash }

        if metricUnits.contains(unit) {
            let rounded = value >= 200 ? halfUp(value / 5) * 5 : halfUp(value)
            return "\(Int(rounded)) \(unit)"
        }

        var whole = Int(value.rounded(.down))
        let frac = value - Double(whole)

        var bestValue = 0.0
        var bestGlyph = ""
        var bestErr = 9.0
        for (fval, glyph) in fractions {
            let err = abs(frac - fval)
            if err < bestErr {
                bestErr = err
                bestValue = fval
                bestGlyph = glyph
            }
        }
        if bestValue == 1.0 {
            whole += 1
            bestGlyph = ""
        }

        let amountStr: String
        if whole > 0 && !bestGlyph.isEmpty {
            amountStr = "\(whole) \(bestGlyph)"
        } else if whole > 0 {
            amountStr = "\(whole)"
        } else if !bestGlyph.isEmpty {
            amountStr = bestGlyph
        } else {
            return frac > 0 ? "pinch" : "0"
        }

        return unit.isEmpty ? amountStr : "\(amountStr) \(unit)"
    }

    /// Convenience: scale one amount by a factor and format it. amount 0 → em dash.
    static func scaledDisplay(amount: Double, unit: String, factor: Double) -> String {
        amount == 0 ? emDash : formatAmount(amount * factor, unit: unit)
    }

    /// Scale an ingredient list (amount 0 rows pass through unscaled).
    static func scale(_ ingredients: [Ingredient], baseYield: Int, targetYield: Int) -> [ScaledRow] {
        let factor = Double(targetYield) / Double(baseYield)
        return ingredients.map { ing in
            let scaled = ing.amount * factor
            return ScaledRow(
                ingredient: ing,
                scaledAmount: ing.amount == 0 ? 0 : scaled,
                display: scaledDisplay(amount: ing.amount, unit: ing.unit, factor: factor)
            )
        }
    }
}

/// A locally-scaled ingredient row (client mirror of ScaledIngredient).
struct ScaledRow: Identifiable, Hashable {
    var ingredient: Ingredient
    var scaledAmount: Double
    var display: String

    var id: String { ingredient.id }
    var section: String? { ingredient.section }
    var name: String { ingredient.name }
    var note: String? { ingredient.note }
}

extension ScalingEngine {
    /// Build the same payload the server's /scale returns, locally.
    ///
    /// This engine is a verbatim port of `api/app/services/scaling.py` with matching
    /// test tables, so an offline scale is identical to an online one rather than an
    /// approximation — which is what makes serving a cached recipe honest.
    static func offlineScaleResponse(_ recipe: RecipeFull, target: Int) throws -> ScaleResponse {
        let rows = scale(recipe.currentVersion.ingredients,
                         baseYield: recipe.baseYield, targetYield: target)
        return ScaleResponse(
            slug: recipe.slug,
            baseYield: recipe.baseYield,
            targetYield: target,
            yieldWord: recipe.yieldWord,
            ingredients: rows.map {
                ScaledIngredient(amount: $0.ingredient.amount, unit: $0.ingredient.unit,
                                 name: $0.name, note: $0.note, section: $0.section,
                                 scaledAmount: $0.scaledAmount, display: $0.display)
            })
    }
}
