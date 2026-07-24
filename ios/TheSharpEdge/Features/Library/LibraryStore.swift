import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published var status: LibraryStatus?
    @Published var query = ""
    @Published var groups: [Grouping.BookGroup] = []
    @Published var isSearching = false
    @Published var searchError: String?
    @Published var didSearch = false

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
            let hits = try await source.search(q, topK: 20)
            groups = Grouping.byBook(hits)
        } catch {
            groups = []
            searchError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        isSearching = false
    }
}
