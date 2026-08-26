import Foundation

extension Collection {
    /// Index without trapping. A translation can be a row shorter than the recipe
    /// if a model dropped a line; a reading lens must never crash the screen.
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
