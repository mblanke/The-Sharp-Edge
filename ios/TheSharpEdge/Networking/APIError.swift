import Foundation

/// Typed API errors. Server sends RFC-7807 problem+json on failures.
enum APIError: Error, LocalizedError, Equatable {
    case badURL
    case notFound
    case unauthorized
    case atlasDown              // 502 — Atlas/rag-api/LLM router unreachable
    case slugTaken(String)      // 409 — create only; fixable inline
    case server(status: Int, detail: String?)
    case decoding(String)
    case transport(String)
    /// This device hosts its own notebook, so there is no server behind the feature
    /// being asked for. The Library and Ask need the owner's private cookbook corpus,
    /// which never leaves their deployment (CLAUDE.md §1).
    ///
    /// The UI hides those routes in local mode rather than showing them disabled, so
    /// this is a backstop for a deep link or a stale launch argument — not the way a
    /// person is expected to meet the limitation.
    case localOnly(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server URL is invalid."
        case .notFound: return "Not found."
        case .unauthorized: return "Not authorized — set your API token in Settings."
        case .atlasDown: return "The library/assistant service is unreachable right now."
        case let .slugTaken(detail): return detail
        case let .server(status, detail): return detail ?? "Server error (\(status))."
        case let .decoding(msg): return "Couldn't read the server response. \(msg)"
        case let .transport(msg): return msg
        case let .localOnly(what): return "\(what) needs a recipe server. This iPad is using its own notebook."
        }
    }
}

/// RFC-7807 problem+json body.
struct ProblemDetail: Decodable {
    var title: String?
    var detail: String?
    var status: Int?
}
