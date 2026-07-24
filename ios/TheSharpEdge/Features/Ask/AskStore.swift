import SwiftUI

struct ChatTurn: Identifiable {
    let id = UUID()
    var role: String            // "user" | "assistant"
    var text: String
    var citations: [Citation] = []
    var sources: [Source] = []
    var streaming: Bool = false
}

@MainActor
final class AskStore: ObservableObject {
    @Published var turns: [ChatTurn] = []
    @Published var input = ""
    @Published var isStreaming = false
    @Published var conversationId: UUID?
    @Published var recent: [ConversationSummary] = []
    @Published var errorText: String?

    private var streamTask: Task<Void, Never>?

    func loadRecent(_ source: DataSource) async {
        recent = (try? await source.conversations()) ?? []
    }

    func newConversation() {
        streamTask?.cancel()
        turns = []
        conversationId = nil
        isStreaming = false
        errorText = nil
    }

    func send(_ source: DataSource, scopeSlug: String?) {
        let question = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isStreaming else { return }
        input = ""
        errorText = nil
        turns.append(ChatTurn(role: "user", text: question))
        var assistant = ChatTurn(role: "assistant", text: "", streaming: true)
        turns.append(assistant)
        let assistantIndex = turns.count - 1
        isStreaming = true

        let req = AskRequest(question: question, conversationId: conversationId,
                             scope: AskScope(recipeSlug: scopeSlug), topK: 8)

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in source.ask(req) {
                    if Task.isCancelled { break }
                    switch event.event {
                    case "meta":
                        if let meta = decode(AskMeta.self, event.data), let id = UUID(uuidString: meta.conversationId) {
                            self.conversationId = id
                        }
                    case "token":
                        if let tok = decode(AskToken.self, event.data) {
                            assistant.text += tok.t
                            self.turns[assistantIndex].text = assistant.text
                        }
                    case "done":
                        if let done = decode(AskDone.self, event.data) {
                            self.turns[assistantIndex].citations = done.citations
                            self.turns[assistantIndex].sources = done.sources
                        }
                    case "error":
                        let detail = decode(AskError.self, event.data)?.detail ?? "The assistant failed to answer."
                        self.errorText = detail
                    default:
                        break
                    }
                }
            } catch {
                self.errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            self.turns[assistantIndex].streaming = false
            self.isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        isStreaming = false
        if let last = turns.indices.last { turns[last].streaming = false }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: String) -> T? {
        guard let d = data.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: d)
    }
}
