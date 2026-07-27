import SwiftUI

@MainActor
final class ShoppingStore: ObservableObject {
    @Published var items: [ShoppingItem] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var shareText = ""

    /// Everything on the list, in the order it was added. "To taste" items are no
    /// longer added at all — you do not buy "salt and pepper, to taste".
    var toBuy: [ShoppingItem] { items }
    var remaining: Int { items.filter { !$0.checked }.count }

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

    func removeMany(_ source: DataSource, _ ids: Set<UUID>) async {
        guard !ids.isEmpty else { return }
        do {
            try await source.removeShoppingItems(Array(ids))
            items.removeAll { ids.contains($0.id) }
            shareText = (try? await source.shoppingText()) ?? shareText
        } catch {
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
