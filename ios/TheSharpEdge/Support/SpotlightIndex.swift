import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

/// Every recipe the app can show, in the iPad's own search. Typing "goulash" on the
/// Home Screen opens the recipe — the QR card's job, for a device with no card in hand.
///
/// Titles, categories and meta lines only. Ingredient and method text stay out of the
/// on-device index: local-mode notebooks are the cook's own, but server-mode lists can
/// include recipes drafted from copyrighted books (CLAUDE.md §1), and the index is
/// readable by the OS outside this app's sandbox.
enum SpotlightIndex {
    static let domain = "recipes"
    static let activityType = "com.blanke.thesharpedge.recipe"

    static func slug(from activity: NSUserActivity) -> String? {
        if activity.activityType == CSSearchableItemActionType {
            return activity.userInfo?[CSSearchableItemActivityIdentifier] as? String
        }
        if activity.activityType == activityType {
            return activity.userInfo?["slug"] as? String
        }
        return nil
    }

    /// Replaces the whole index with `cards`. Cheap (a few dozen items) and idempotent,
    /// so it runs after every list load rather than tracking deltas.
    static func reindex(_ cards: [RecipeCard]) {
        guard CSSearchableIndex.isIndexingAvailable() else { return }
        let items = cards.map { card -> CSSearchableItem in
            let attrs = CSSearchableItemAttributeSet(contentType: .text)
            attrs.title = card.title
            attrs.contentDescription = [card.category, card.meta].compactMap { $0 }.joined(separator: " · ")
            attrs.keywords = [card.category, "recipe", "The Sharp Edge"] + (card.gf ? ["gluten-free", "GF"] : [])
            let item = CSSearchableItem(uniqueIdentifier: card.slug, domainIdentifier: domain, attributeSet: attrs)
            item.expirationDate = .distantFuture
            return item
        }
        let index = CSSearchableIndex.default()
        index.deleteSearchableItems(withDomainIdentifiers: [domain]) { _ in
            index.indexSearchableItems(items) { _ in }
        }
    }

    /// Handoff + Spotlight continuation for an open recipe: an iPhone can pick up the
    /// recipe the iPad is showing, and the same activity carries the web URL.
    static func activity(for recipe: RecipeFull, webURL: URL?) -> NSUserActivity {
        let activity = NSUserActivity(activityType: activityType)
        activity.title = recipe.title
        activity.userInfo = ["slug": recipe.slug]
        activity.requiredUserInfoKeys = ["slug"]
        activity.isEligibleForHandoff = true
        activity.isEligibleForSearch = true
        activity.webpageURL = webURL
        return activity
    }
}
