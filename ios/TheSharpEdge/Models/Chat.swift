import Foundation

/// Mirrors api/app/schemas/chat.py + the /ask SSE payloads.

struct AskScope: Codable {
    var recipeSlug: String?
    enum CodingKeys: String, CodingKey { case recipeSlug = "recipe_slug" }
}

struct AskRequest: Codable {
    var question: String
    var conversationId: UUID?
    var scope: AskScope
    var topK: Int

    init(question: String, conversationId: UUID? = nil, scope: AskScope = AskScope(recipeSlug: nil), topK: Int = 8) {
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

    var id: Int { n }

    enum CodingKeys: String, CodingKey {
        case n, title
        case sourcePath = "source_path"
        case heading, page
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

    var id: Int { n }

    enum CodingKeys: String, CodingKey {
        case n, title
        case sourcePath = "source_path"
        case heading, page, text
    }
}

struct ChunkOut: Codable, Hashable, Identifiable {
    var text: String
    var sourcePath: String?
    var title: String?
    var heading: String?
    var page: Int?
    var score: Double?
    var rerankScore: Double?

    var id: String { "\(title ?? "")|\(page ?? -1)|\(heading ?? "")" }

    enum CodingKeys: String, CodingKey {
        case text
        case sourcePath = "source_path"
        case title, heading, page, score
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

struct AskDone: Codable {
    var citations: [Citation]
    var sources: [Source]
}

struct AskError: Codable {
    var detail: String
}
