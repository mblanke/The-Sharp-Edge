import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published var status: LibraryStatus?
    @Published var query = ""
    @Published var groups: [Grouping.BookGroup] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var didSearch = false
    /// Restrict the search to one source file. Empty = the whole shelf.
    @Published var bookFilter = "" {
        didSet { if didSearch { pendingRefilter = true } }
    }
    /// Set when the scope changed after a search, so the view can re-run it.
    var pendingRefilter = false

    /// Books worth offering as a filter: files the index actually holds something for.
    /// Offering a book with no chunks would scope a question down to silence.
    var searchableBooks: [BookOut] {
        (status?.books ?? []).filter { $0.status == nil || $0.status == "indexed" }
    }

    func loadStatus(_ source: DataSource) async {
        status = try? await source.libraryStatus()
    }

    func search(_ source: DataSource) async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else { return }
        isSearching = true
        searchError = nil
        didSearch = true
        do {
            let hits = try await source.search(q, topK: 20, book: bookFilter.isEmpty ? nil : bookFilter)
            groups = Grouping.byBook(hits)
        } catch {
            groups = []
            searchError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isSearching = false
    }
}
