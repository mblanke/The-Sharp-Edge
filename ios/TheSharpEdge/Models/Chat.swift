import Foundation

/// Mirrors api/app/schemas/chat.py + the /ask SSE payloads.

struct AskScope: Codable {
    var recipeSlug: String?
    /// Source file names to restrict the answer to. The server has accepted this since
    /// book scope shipped; the phone never sent it, which is why naming a book only
    /// worked by typing it into the question and hoping retrieval noticed.
    var books: [String]?
    enum CodingKeys: String, CodingKey {
        case recipeSlug = "recipe_slug"
        case books
    }
}

struct AskRequest: Codable {
    var question: String
    var conversationId: UUID?
    var scope: AskScope
    var topK: Int

    init(question: String, conversationId: UUID? = nil, scope: AskScope = AskScope(recipeSlug: nil, books: nil), topK: Int = 8) {
        self.question = question
        self.conversationId = conversationId
        self.scope = scope
        self.topK = topK
    }

    enum CodingKeys: String, CodingKey {
        case question
        case conversationId = "conversation_id"
        case scope
        case topK = "top_k"
    }
}

struct Citation: Codable, Hashable, Identifiable {
    var n: Int
    var title: String?
    var sourcePath: String?
    var heading: String?
    var page: Int?
    /// pdf | epub | mkv … A transcript carries a `page` that is an artefact of
    /// chunking, so media sources must not offer to open one.
    var fileType: String?

    var id: Int { n }
    var isMedia: Bool { MediaKinds.contains(fileType) }

    enum CodingKeys: String, CodingKey {
        case n, title
        case sourcePath = "source_path"
        case heading, page
        case fileType = "file_type"
    }
}

/// Sources with no page structure at all.
enum MediaKinds {
    static let all: Set<String> = ["mkv", "mp4", "webm", "avi", "mov", "m4v", "mp3", "wav", "m4a"]
    static func contains(_ fileType: String?) -> Bool {
        guard let t = fileType?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) else { return false }
        return all.contains(t)
    }
}

/// The richer per-source payload carried on the SSE `done` event.
struct Source: Codable, Hashable, Identifiable {
    var n: Int
    var title: String?
    var sourcePath: String?
    var heading: String?
    var page: Int?
    var text: String?
    var fileType: String?

    var id: Int { n }
    var isMedia: Bool { MediaKinds.contains(fileType) }

    enum CodingKeys: String, CodingKey {
        case n, title
        case sourcePath = "source_path"
        case heading, page, text
        case fileType = "file_type"
    }
}

struct ChunkOut: Codable, Hashable, Identifiable {
    var text: String
    var sourcePath: String?
    var title: String?
    var heading: String?
    var page: Int?
    var fileType: String?
    var score: Double?
    var rerankScore: Double?

    var id: String { "\(title ?? "")|\(page ?? -1)|\(heading ?? "")" }

    var isMedia: Bool { MediaKinds.contains(fileType) }

    enum CodingKeys: String, CodingKey {
        case text
        case sourcePath = "source_path"
        case title, heading, page, score
        case fileType = "file_type"
        case rerankScore = "rerank_score"
    }
}

struct MessageOut: Codable, Hashable, Identifiable {
    var id: UUID
    var role: String
    var content: String
    var citations: [Citation]
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, role, content, citations
        case createdAt = "created_at"
    }
}

struct ConversationSummary: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
    }
}

struct ConversationFull: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String?
    var createdAt: Date
    var messages: [MessageOut]

    enum CodingKeys: String, CodingKey {
        case id, title
        case createdAt = "created_at"
        case messages
    }
}

// MARK: - SSE event payloads

struct AskMeta: Codable {
    var conversationId: String
    var chunks: Int
    enum CodingKeys: String, CodingKey {
        case conversationId = "conversation_id"
        case chunks
    }
}

struct AskToken: Codable {
    var t: String
}

/// Set when the question named an authority this shelf cannot answer for.
/// `ungrounded` catches an answer with no citations at all; this catches one whose
/// citations point at the wrong book — the failure that had "how does Escoffier build
/// an espagnole?" answered six times in Escoffier's name from the CIA's pages.
struct Attribution: Codable, Hashable {
    var absent: [String]
    var unretrieved: [String]
    var sources: [String]
    var note: String
}

struct AskDone: Codable {
    var citations: [Citation]
    var sources: [Source]
    var ungrounded: Bool?
    var attribution: Attribution?
}

struct AskError: Codable {
    var detail: String
}
