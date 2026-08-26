import Foundation

/// Live backend client. Bearer token is attached ONLY to write routes (POST/PUT recipes);
/// reads, scale, search, and ask are unauthenticated (the stack sits behind Tailscale).
final class APIClient: DataSource {
    private let base: URL
    private let endpoints: Endpoints
    private let tokenProvider: () -> String?
    private let session: URLSession

    init(base: URL, tokenProvider: @escaping () -> String?, session: URLSession = .shared) {
        self.base = base
        self.endpoints = Endpoints(base: base)
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Core

    private func request(_ url: URL?, method: String = "GET", authed: Bool = false, body: Data? = nil) throws -> URLRequest {
        guard let url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.httpBody = body
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if authed, let token = tokenProvider(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return req
    }

    private func run<T: Decodable>(_ req: URLRequest, as type: T.Type) async throws -> T {
        let (data, _) = try await perform(req)
        do {
            return try JSONCoding.decoder.decode(T.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    private func perform(_ req: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, data: data)
        }
        return (data, http)
    }

    private func mapError(status: Int, data: Data) -> APIError {
        let detail = (try? JSONCoding.decoder.decode(ProblemDetail.self, from: data))?.detail
        switch status {
        case 401: return .unauthorized
        case 404: return .notFound
        // Create only: the slug is already taken. Fixable inline, so it gets its own case.
        case 409: return .slugTaken(detail ?? "That slug is already in use.")
        case 502: return .atlasDown
        default: return .server(status: status, detail: detail)
        }
    }

    // MARK: - Recipes

    func listRecipes() async throws -> [RecipeCard] {
        try await run(request(endpoints.recipes(status: "active")), as: [RecipeCard].self)
    }

    func recipe(_ slug: String) async throws -> RecipeFull {
        try await run(request(endpoints.recipe(slug)), as: RecipeFull.self)
    }

    func versions(_ slug: String) async throws -> [VersionSummary] {
        try await run(request(endpoints.versions(slug)), as: [VersionSummary].self)
    }

    func version(_ slug: String, _ n: Int) async throws -> VersionOut {
        try await run(request(endpoints.version(slug, n)), as: VersionOut.self)
    }

    func restoreVersion(_ slug: String, _ n: Int) async throws -> RecipeFull {
        try await run(request(endpoints.restoreVersion(slug, n), method: "POST", authed: true),
                      as: RecipeFull.self)
    }

    func scale(_ slug: String, target: Int) async throws -> ScaleResponse {
        let body = try JSONCoding.encoder.encode(ScaleRequest(targetYield: target))
        return try await run(request(endpoints.scale(slug), method: "POST", body: body), as: ScaleResponse.self)
    }

    func updateRecipe(_ slug: String, _ payload: RecipeUpdate) async throws -> RecipeFull {
        let body = try JSONCoding.encoder.encode(payload)
        return try await run(request(endpoints.recipe(slug), method: "PUT", authed: true, body: body), as: RecipeFull.self)
    }

    func createRecipe(_ payload: RecipeCreate) async throws -> RecipeFull {
        let body = try JSONCoding.encoder.encode(payload)
        return try await run(request(endpoints.createRecipe(), method: "POST", authed: true, body: body), as: RecipeFull.self)
    }

    // MARK: - Shopping list

    func shoppingList() async throws -> [ShoppingItem] {
        try await run(request(endpoints.shopping()), as: ShoppingList.self).items
    }

    /// Plain text for the share sheet — AnyList, Notes and Reminders all accept it.
    func shoppingText() async throws -> String {
        guard let url = endpoints.shoppingText() else { throw APIError.badURL }
        var req = URLRequest(url: url)
        req.setValue("text/plain", forHTTPHeaderField: "Accept")
        let (data, _) = try await perform(req)
        return String(data: data, encoding: .utf8) ?? ""
    }

    func addToShopping(_ slug: String, targetYield: Int?) async throws -> [ShoppingItem] {
        let body = try JSONCoding.encoder.encode(ShoppingAdd(slug: slug, targetYield: targetYield))
        return try await run(request(endpoints.shoppingAdd(), method: "POST", authed: true, body: body),
                             as: ShoppingList.self).items
    }

    func setShoppingChecked(_ id: UUID, _ checked: Bool) async throws -> ShoppingItem {
        let body = try JSONCoding.encoder.encode(ShoppingToggle(checked: checked))
        return try await run(request(endpoints.shoppingItem(id), method: "PATCH", authed: true, body: body),
                             as: ShoppingItem.self)
    }

    func removeShoppingItem(_ id: UUID) async throws {
        _ = try await perform(request(endpoints.shoppingItem(id), method: "DELETE", authed: true))
    }

    func removeShoppingItems(_ ids: [UUID]) async throws {
        guard !ids.isEmpty else { return }
        let body = try JSONCoding.encoder.encode(["ids": ids.map { $0.uuidString.lowercased() }])
        _ = try await perform(request(endpoints.shoppingDelete(), method: "POST", authed: true, body: body))
    }

    func clearShopping(checkedOnly: Bool) async throws {
        _ = try await perform(request(endpoints.shoppingClear(checkedOnly: checkedOnly),
                                      method: "DELETE", authed: true))
    }

    // MARK: - Parse helpers (unauthenticated)

    func parseIngredients(_ lines: [String], lang: CaptureLanguage) async throws -> [Ingredient] {
        let body = try JSONCoding.encoder.encode(ParseIngredientsRequest(lines: lines, lang: lang.rawValue))
        let res = try await run(request(endpoints.parseIngredients(), method: "POST", body: body),
                                as: ParseIngredientsResponse.self)
        return res.ingredients
    }

    /// Photo upload gets its own session. The shared one is tuned for small,
    /// quick JSON calls; a multi-hundred-KB body over Tailscale needs to wait for
    /// connectivity rather than fail, and to allow cellular and low-data modes.
    private static let uploadSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 300
        config.timeoutIntervalForResource = 600
        config.waitsForConnectivity = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        return URLSession(configuration: config)
    }()

    func parsePhoto(_ jpeg: Data) async throws -> PhotoDraft {
        guard let url = endpoints.parsePhoto() else { throw APIError.badURL }
        let boundary = "sharp-edge-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"photo\"; filename=\"page.jpg\"\r\n".utf8))
        body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
        body.append(jpeg)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenProvider(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        // The first read after idle waits for the vision model to load on the GB10s.
        req.timeoutInterval = 300

        let data: Data
        let response: URLResponse
        do {
            // upload(for:from:) streams the body, unlike data(for:) with httpBody.
            (data, response) = try await Self.uploadSession.upload(for: req, from: body)
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw APIError.transport("No HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw mapError(status: http.statusCode, data: data)
        }
        do {
            return try JSONCoding.decoder.decode(PhotoDraft.self, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    func translate(_ body: TranslateRequest) async throws -> TranslateResponse {
        try await run(request(endpoints.translate(), method: "POST", authed: true,
                              body: try JSONCoding.encoder.encode(body)),
                      as: TranslateResponse.self)
    }

    func slug(for title: String) async throws -> SlugResponse {
        let body = try JSONCoding.encoder.encode(SlugRequest(title: title))
        return try await run(request(endpoints.parseSlug(), method: "POST", body: body), as: SlugResponse.self)
    }

    func category(for spoken: String, lang: CaptureLanguage) async throws -> String? {
        let body = try JSONCoding.encoder.encode(CategoryRequest(spoken: spoken, lang: lang.rawValue))
        return try await run(request(endpoints.parseCategory(), method: "POST", body: body),
                             as: CategoryResponse.self).category
    }

    // MARK: - Library / search / conversations

    /// RFC-7807 `detail`, when the server sent one.
    private static func problemDetail(_ data: Data) -> String? {
        (try? JSONCoding.decoder.decode(ProblemDetail.self, from: data))?.detail
    }

    func sourcePage(path: String, page: Int) async throws -> Data {
        var comps = URLComponents(url: base.appendingPathComponent("api/v1/library/source"),
                                  resolvingAgainstBaseURL: false)
        comps?.queryItems = [URLQueryItem(name: "path", value: path),
                             URLQueryItem(name: "page", value: String(page))]
        guard let url = comps?.url else { throw APIError.badURL }
        var req = URLRequest(url: url)
        if let token = tokenProvider(), !token.isEmpty {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else { throw APIError.transport("No response") }
            guard (200..<300).contains(http.statusCode) else {
                if http.statusCode == 401 { throw APIError.unauthorized }
                if http.statusCode == 404 {
                    throw APIError.server(status: 404, detail: Self.problemDetail(data)
                        ?? "That page isn't available.")
                }
                throw APIError.server(status: http.statusCode, detail: Self.problemDetail(data))
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.transport(error.localizedDescription)
        }
    }

    func search(_ q: String, topK: Int) async throws -> [ChunkOut] {
        try await run(request(endpoints.search(q: q, topK: topK)), as: [ChunkOut].self)
    }

    func libraryStatus() async throws -> LibraryStatus {
        try await run(request(endpoints.libraryBooks()), as: LibraryStatus.self)
    }

    func conversations() async throws -> [ConversationSummary] {
        try await run(request(endpoints.conversations()), as: [ConversationSummary].self)
    }

    func conversation(_ id: UUID) async throws -> ConversationFull {
        try await run(request(endpoints.conversation(id)), as: ConversationFull.self)
    }

    // MARK: - Ask (SSE)

    func ask(_ ask: AskRequest) -> AsyncThrowingStream<SSEEvent, Error> {
        do {
            let body = try JSONCoding.encoder.encode(ask)
            var req = try request(endpoints.ask(), method: "POST", body: body)
            req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
            req.timeoutInterval = 120
            return SSEClient.stream(req, session: session)
        } catch {
            return AsyncThrowingStream { $0.finish(throwing: error) }
        }
    }

    // MARK: - Misc

    func health() async throws -> Bool {
        let req = try request(endpoints.healthz())
        let (_, http) = try await perform(req)
        return http.statusCode == 200
    }

    func qrURL(_ slug: String) -> URL? { endpoints.qr(slug) }
}
