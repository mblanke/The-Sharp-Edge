import SwiftUI

@MainActor
final class ShoppingStore: ObservableObject {
    @Published var items: [ShoppingItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var shareText = ""

    /// Things you buy, in the order they were added.
    var toBuy: [ShoppingItem] { items.filter { !$0.toTaste } }
    /// "Salt, to taste" — you don't buy these, you check you have them.
    var staples: [ShoppingItem] { items.filter { $0.toTaste } }
    var remaining: Int { toBuy.filter { !$0.checked }.count }

    func load(_ source: DataSource) async {
        isLoading = true
        error = nil
        do {
            items = try await source.shoppingList()
            shareText = (try? await source.shoppingText()) ?? ""
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isLoading = false
    }

    func add(_ source: DataSource, slug: String, targetYield: Int?) async -> Bool {
        do {
            items = try await source.addToShopping(slug, targetYield: targetYield)
            shareText = (try? await source.shoppingText()) ?? ""
            return true
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func toggle(_ source: DataSource, _ item: ShoppingItem) async {
        // Optimistic: ticking things off in a shop should feel instant.
        guard let i = items.firstIndex(where: { $0.id == item.id }) else { return }
        let previous = items[i].checked
        items[i].checked.toggle()
        do {
            let updated = try await source.setShoppingChecked(item.id, items[i].checked)
            items[i] = updated
            shareText = (try? await source.shoppingText()) ?? shareText
        } catch {
            items[i].checked = previous
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func remove(_ source: DataSource, _ item: ShoppingItem) async {
        do {
            try await source.removeShoppingItem(item.id)
            items.removeAll { $0.id == item.id }
            shareText = (try? await source.shoppingText()) ?? shareText
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func clear(_ source: DataSource, checkedOnly: Bool) async {
        do {
            try await source.clearShopping(checkedOnly: checkedOnly)
            await load(source)
        } catch {
            self.error = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }
}
