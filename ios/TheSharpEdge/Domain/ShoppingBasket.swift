import Foundation

/// A shopping list held on the device, built on `ShoppingMerge`.
///
/// This is the bridge between the wire model (`ShoppingItem`, which the UI renders) and
/// the merge arithmetic (`ShoppingMerge.Line`). It exists so there is exactly one
/// implementation of "add a recipe to the list" on the device — used by the offline
/// fixtures source today and by the local notebook next.
///
/// Before this, `SampleDataSource` carried its own same-name/same-unit sum with a
/// drifted gluten list and a hardcoded `aisle: "Other"`. That was defensible while the
/// server was always the real answer. It is not defensible in local mode, where nothing
/// else is going to do the arithmetic.
struct ShoppingBasket {

    private(set) var items: [ShoppingItem] = []

    init(items: [ShoppingItem] = []) { self.items = items }

    /// Add a scaled recipe. Quantities **add** to existing lines rather than replacing
    /// them, which is the entire point of the list.
    ///
    /// Checked state and item identity survive: a line you already ticked off keeps its
    /// id and its tick when a second recipe contributes to it.
    @discardableResult
    mutating func add(_ rows: [ScaledRow], from slug: String) -> [ShoppingItem] {
        let existing = items.map(line)
        let incoming = rows.map {
            ShoppingMerge.Line(name: $0.name, amount: $0.scaledAmount,
                               unit: $0.ingredient.unit, toTaste: $0.scaledAmount == 0,
                               recipes: [slug])
        }
        rebuild(from: existing + incoming)
        return items
    }

    mutating func setChecked(_ id: UUID, _ checked: Bool) throws -> ShoppingItem {
        guard let i = items.firstIndex(where: { $0.id == id }) else { throw APIError.notFound }
        items[i].checked = checked
        return items[i]
    }

    mutating func remove(_ ids: [UUID]) {
        items.removeAll { ids.contains($0.id) }
    }

    mutating func clear(checkedOnly: Bool) {
        items.removeAll { checkedOnly ? $0.checked : true }
    }

    /// Plain text for the share sheet, grouped by aisle so it can be walked once.
    /// Checked items are left out — you have those already.
    func text(title: String = "Shopping list") -> String {
        let lines = items.filter { !$0.checked }.map(line)
        let walked = lines.enumerated()
            .sorted { a, b in
                let ra = Aisles.rank(a.element.aisle), rb = Aisles.rank(b.element.aisle)
                return ra == rb ? a.offset < b.offset : ra < rb
            }
            .map(\.element)
        return ShoppingMerge.asText(walked, title: title, groupBy: { $0.aisle })
    }

    // MARK: - Bridging

    private func line(_ item: ShoppingItem) -> ShoppingMerge.Line {
        ShoppingMerge.Line(name: item.name, amount: item.amount, unit: item.unit,
                           toTaste: item.toTaste, recipes: item.recipes,
                           checked: item.checked)
    }

    /// Re-merge and map back to wire items, reusing the id of the line that was already
    /// on the list so SwiftUI identity — and the checkbox — survives.
    private mutating func rebuild(from lines: [ShoppingMerge.Line]) {
        var idsByKey: [String: UUID] = [:]
        var checkedByKey: [String: Bool] = [:]
        for item in items {
            let key = line(item).key
            idsByKey[key] = item.id
            checkedByKey[key] = item.checked
        }

        items = ShoppingMerge.merge(lines).map { merged in
            ShoppingItem(id: idsByKey[merged.key] ?? UUID(),
                         name: merged.name, amount: merged.amount, unit: merged.unit,
                         display: merged.display, toTaste: merged.toTaste,
                         checked: checkedByKey[merged.key] ?? false,
                         recipes: merged.recipes, checkGluten: merged.checkGluten,
                         aisle: merged.aisle)
        }
    }
}
