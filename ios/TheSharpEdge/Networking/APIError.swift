import Foundation

/// Typed API errors. Server sends RFC-7807 problem+json on failures.
enum APIError: Error, LocalizedError, Equatable {
    case badURL
    case notFound
    case unauthorized
    case atlasDown              // 502 — Atlas/rag-api/LLM router unreachable
    case server(status: Int, detail: String?)
    case decoding(String)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .badURL: return "The server URL is invalid."
        case .notFound: return "Not found."
        case .unauthorized: return "Not authorized — set your API token in Settings."
        case .atlasDown: return "The library/assistant service is unreachable right now."
        case let .server(status, detail): return detail ?? "Server error (\(status))."
        case let .decoding(msg): return "Couldn't read the server response. \(msg)"
        case let .transport(msg): return msg
        }
    }
}

/// RFC-7807 problem+json body.
struct ProblemDetail: Decodable {
    var title: String?
    var detail: String?
    var status: Int?
}
