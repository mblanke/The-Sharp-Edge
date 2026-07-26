import SwiftUI

struct AskView: View {
    var scopeSlug: String?
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var store = AskStore()
    @State private var expandedSource: Int?

    var body: some View {
        VStack(spacing: 0) {
            if let slug = scopeSlug {
                scopeBanner(slug)
            }
            chatScroll
            inputBar
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Ask")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { store.newConversation() } label: { Image(systemName: "square.and.pencil") }
            }
        }
        .task(id: config.useSampleData) { await store.loadRecent(env.dataSource) }
        .onAppear {
            #if DEBUG
            if ProcessInfo.processInfo.environment["UITEST_ASK"] == "1", store.turns.isEmpty {
                store.input = "How does Escoffier build an espagnole?"
                store.send(env.dataSource, scopeSlug: scopeSlug)
            }
            #endif
        }
    }

    private func scopeBanner(_ slug: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "link").foregroundStyle(Theme.accent)
            Text("Scoped to this recipe").font(Typography.mono(12)).foregroundStyle(Theme.faint)
            Spacer()
        }
        .padding(.horizontal, Theme.Space.l).padding(.vertical, 8)
        .background(Theme.card)
    }

    private var chatScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.Space.l) {
                    if store.turns.isEmpty { emptyState }
                    ForEach(store.turns) { turn in
                        turnView(turn).id(turn.id)
                    }
                    if let error = store.errorText {
                        Text(error).font(Typography.body(14)).foregroundStyle(Theme.accent)
                    }
                }
                .padding(Theme.Space.xl)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            // Follow the answer as it streams, but do NOT animate: this fires on every
            // flush, and animating a scroll over a growing text block repeatedly is what
            // made long answers freeze. Animate only when a new turn appears.
            .onChange(of: store.turns.last?.text) { _, _ in
                guard let last = store.turns.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
            .onChange(of: store.turns.count) { _, _ in
                guard let last = store.turns.last else { return }
                withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Ask the library").font(Typography.display(26)).foregroundStyle(Theme.ink)
            Text("Answers cite the cookbooks on the shelf. Local models only — corpus never leaves your network.")
                .font(Typography.body(15)).foregroundStyle(Theme.faint)
            if !store.recent.isEmpty {
                Text("Recent").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.accent).padding(.top, 8)
                ForEach(store.recent) { conv in
                    Button {
                        Task { await load(conv) }
                    } label: {
                        HStack {
                            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.faint)
                            Text(conv.title ?? "Conversation").font(Typography.body(15)).foregroundStyle(Theme.ink)
                                .lineLimit(1)
                            Spacer()
                        }
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 20)
    }

    private func turnView(_ turn: ChatTurn) -> some View {
        VStack(alignment: turn.role == "user" ? .trailing : .leading, spacing: Theme.Space.s) {
            if turn.role == "user" {
                Text(turn.text)
                    .font(Typography.body(16))
                    .foregroundStyle(Theme.offWhite)
                    .padding(Theme.Space.m)
                    .background(Theme.primaryDeep, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            } else {
                VStack(alignment: .leading, spacing: Theme.Space.m) {
                    if turn.text.isEmpty && turn.streaming {
                        HStack(spacing: 6) { ProgressView().tint(Theme.primary); Text("Thinking…").font(Typography.mono(13)).foregroundStyle(Theme.faint) }
                    } else {
                        Text(turn.text)
                            .font(Typography.body(16)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if !turn.citations.isEmpty {
                        citationChips(turn)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func citationChips(_ turn: ChatTurn) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(turn.citations) { c in
                        Button {
                            expandedSource = (expandedSource == c.n) ? nil : c.n
                        } label: {
                            Chip(text: "[\(c.n)] \(c.title ?? "source")", selected: expandedSource == c.n)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let n = expandedSource, let src = turn.sources.first(where: { $0.n == n }) {
                CardSurface {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(src.title ?? "Source").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.inkAccent)
                            if let p = src.page { Text("p. \(p)").font(Typography.mono(12)).foregroundStyle(Theme.faint) }
                        }
                        if let heading = src.heading { Text(heading).font(Typography.mono(12)).foregroundStyle(Theme.accent) }
                        if let text = src.text { Text(text).font(Typography.body(14)).foregroundStyle(Theme.ink) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: Theme.Space.m) {
            HStack {
                TextField(scopeSlug != nil ? "Ask about this recipe…" : "Ask the library…", text: $store.input, axis: .vertical)
                    .font(Typography.body(16))
                    .lineLimit(1...4)
                    .onSubmit { store.send(env.dataSource, scopeSlug: scopeSlug) }
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(minHeight: Theme.minTouch)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous).stroke(Theme.line, lineWidth: 1))

            if store.isStreaming {
                Button { store.stop() } label: {
                    Image(systemName: "stop.fill").foregroundStyle(Theme.offWhite)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .background(Theme.accent, in: Circle())
                }
            } else {
                Button { store.send(env.dataSource, scopeSlug: scopeSlug) } label: {
                    Image(systemName: "arrow.up").foregroundStyle(Theme.offWhite).font(.system(size: 18, weight: .bold))
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                        .background(store.input.isEmpty ? Theme.faint.opacity(0.4) : Theme.primaryDeep, in: Circle())
                }
                .disabled(store.input.isEmpty)
            }
        }
        .padding(Theme.Space.l)
        .background(Theme.paper)
    }

    private func load(_ conv: ConversationSummary) async {
        if let full = try? await env.dataSource.conversation(conv.id) {
            store.conversationId = full.id
            store.turns = full.messages.map { m in
                ChatTurn(role: m.role, text: m.content, citations: m.citations, sources: [], streaming: false)
            }
        }
    }
}
