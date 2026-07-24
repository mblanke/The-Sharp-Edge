import Foundation

/// Builds URLs for the /api/v1 surface.
struct Endpoints {
    let base: URL

    private func url(_ path: String, query: [String: String?] = [:]) -> URL? {
        guard var comps = URLComponents(url: base.appendingPathComponent("api/v1" + path),
                                        resolvingAgainstBaseURL: false) else { return nil }
        let items = query.compactMap { key, value -> URLQueryItem? in
            guard let value else { return nil }
            return URLQueryItem(name: key, value: value)
        }
        if !items.isEmpty { comps.queryItems = items }
        return comps.url
    }

    func recipes(category: String? = nil, q: String? = nil, gf: Bool? = nil, status: String? = nil) -> URL? {
        url("/recipes", query: [
            "category": category,
            "q": q,
            "gf": gf.map { $0 ? "true" : "false" },
            "status": status,
        ])
    }
    func recipe(_ slug: String) -> URL? { url("/recipes/\(slug)") }
    func versions(_ slug: String) -> URL? { url("/recipes/\(slug)/versions") }
    func scale(_ slug: String) -> URL? { url("/recipes/\(slug)/scale") }
    func qr(_ slug: String) -> URL? { url("/recipes/\(slug)/qr") }
    func createRecipe() -> URL? { url("/recipes") }

    func search(q: String, topK: Int) -> URL? {
        url("/search", query: ["q": q, "top_k": String(topK)])
    }
    func libraryBooks() -> URL? { url("/library/books") }
    func conversations() -> URL? { url("/conversations") }
    func conversation(_ id: UUID) -> URL? { url("/conversations/\(id.uuidString.lowercased())") }
    func ask() -> URL? { url("/ask") }
    func healthz() -> URL? { url("/healthz") }
}
