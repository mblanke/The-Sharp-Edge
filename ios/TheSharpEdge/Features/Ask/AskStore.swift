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

    /// A long answer arrives as ~350 token events. Publishing each one separately means
    /// ~350 SwiftUI invalidations, each re-laying-out a growing text block — which locks
    /// the UI up on device. Tokens are accumulated and flushed at ~12 Hz instead; the
    /// final flush after the loop makes sure nothing is dropped.
    private static let flushInterval: TimeInterval = 0.08

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
            var lastFlush = Date.distantPast

            // The turn can vanish under us — newConversation() empties `turns` and
            // cancellation is cooperative, so never index blindly.
            let withTurn = { (body: (inout ChatTurn) -> Void) in
                self.mutateTurn(at: assistantIndex, body)
            }

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
                            let now = Date()
                            if now.timeIntervalSince(lastFlush) >= Self.flushInterval {
                                lastFlush = now
                                withTurn { $0.text = assistant.text }
                            }
                        }
                    case "done":
                        if let done = decode(AskDone.self, event.data) {
                            withTurn {
                                $0.citations = done.citations
                                $0.sources = done.sources
                            }
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
            withTurn {
                $0.text = assistant.text   // final flush — the last partial buffer
                $0.streaming = false
            }
            self.isStreaming = false
        }
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
        if let last = turns.indices.last { turns[last].streaming = false }
    }

    /// Guarded write — `turns` can be emptied by newConversation() while a stream is
    /// still draining, and an unguarded subscript would crash.
    private func mutateTurn(at index: Int, _ body: (inout ChatTurn) -> Void) {
        guard turns.indices.contains(index) else { return }
        body(&turns[index])
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: String) -> T? {
        guard let d = data.data(using: .utf8) else { return nil }
        return try? JSONCoding.decoder.decode(T.self, from: d)
    }
}
