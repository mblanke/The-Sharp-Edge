import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var store = LibraryStore()
    /// The book page a result points at, once someone asks to see it.
    @State private var opening: SourceTarget?

    struct SourceTarget: Identifiable {
        let id = UUID()
        let title: String
        let path: String
        let page: Int
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                searchBar
                bookScopePicker
                results
                shelf
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $opening) { target in
            SourcePageView(title: target.title, path: target.path, page: target.page)
                .environmentObject(env)
        }
        .task(id: env.generation) {
            await store.loadStatus(env.dataSource)
            #if DEBUG
            // Screenshot/QA hook: run a query on launch so search results can be
            // inspected without driving the keyboard.
            if let q = ProcessInfo.processInfo.environment["UITEST_SEARCH"], !q.isEmpty {
                store.query = q
                await store.search(env.dataSource)
            }
            #endif
        }
    }

    /// What the shelf holds, and — more usefully — what of it is actually searchable.
    /// The file list and the index were never compared before, so a book that failed to
    /// ingest looked exactly like one that worked. A nil status means the coverage
    /// lookup was unavailable; that is "unknown" and must not be drawn as "missing".
    @ViewBuilder private var shelf: some View {
        if let books = store.status?.books, !books.isEmpty {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                Text("On the shelf")
                    .font(Typography.mono(12, weight: .semibold))
                    .textCase(.uppercase)
                    .foregroundStyle(Theme.primary)
                ForEach(books) { book in
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Space.s) {
                        Text(book.name)
                            .font(Typography.body(14)).foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: Theme.Space.s)
                        if let status = book.status {
                            if status == "indexed", let n = book.chunks {
                                Text("\(n) passages")
                                    .font(Typography.mono(11)).foregroundStyle(Theme.faint)
                            } else {
                                Text(status == "thin" ? "barely indexed" : "not indexed")
                                    .font(Typography.mono(11))
                                    .textCase(.uppercase)
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                    Divider().overlay(Theme.line)
                }
            }
            .padding(.top, Theme.Space.m)
        }
    }

    /// Scope the search to one book. Only books the index actually holds are offered —
    /// scoping to an unindexed book would narrow the search down to silence.
    @ViewBuilder private var bookScopePicker: some View {
        let books = store.searchableBooks.filter { $0.kind == "file" || $0.chunks != nil }
        if !books.isEmpty {
            HStack(spacing: Theme.Space.s) {
                Text("In").font(Typography.mono(11)).textCase(.uppercase).foregroundStyle(Theme.faint)
                Picker("Restrict search to one book", selection: $store.bookFilter) {
                    Text("All books").tag("")
                    ForEach(books) { book in Text(book.name).tag(book.name) }
                }
                .pickerStyle(.menu)
                .tint(store.bookFilter.isEmpty ? Theme.faint : Theme.inkAccent)
                Spacer()
            }
            .onChange(of: store.bookFilter) { _, _ in
                guard store.pendingRefilter else { return }
                store.pendingRefilter = false
                Task { await store.search(env.dataSource) }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Eyebrow(text: "Cookbook corpus")
                Text("Library search").font(Typography.display(30)).foregroundStyle(Theme.ink)
            }
            Spacer()
            indexPill
        }
    }

    private var indexPill: some View {
        let ok = store.status?.ragHealth.ok ?? false
        return HStack(spacing: 6) {
            Circle().fill(ok ? Theme.primary : Theme.accent).frame(width: 8, height: 8)
            Text(ok ? "index online" : "index unreachable")
                .font(Typography.mono(12)).foregroundStyle(Theme.faint)
            if let count = store.status?.ragHealth.count {
                Text("· \(count) chunks").font(Typography.mono(12)).foregroundStyle(Theme.faint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.card, in: Capsule())
        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
    }

    private var searchBar: some View {
        HStack(spacing: Theme.Space.m) {
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
                TextField("Search the cookbooks…", text: $store.query)
                    .font(Typography.body(16))
                    .submitLabel(.search)
                    .onSubmit { Task { await store.search(env.dataSource) } }
            }
            .padding(.horizontal, Theme.Space.l)
            .frame(height: Theme.minTouch)
            .background(Theme.card, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1))

            Button { Task { await store.search(env.dataSource) } } label: {
                Text("Search").frame(maxWidth: 110)
            }
            .buttonStyle(PrimaryButtonStyle())
            .frame(maxWidth: 130)
        }
    }

    @ViewBuilder
    private var results: some View {
        if store.isSearching {
            ProgressView().tint(Theme.primary).frame(maxWidth: .infinity).padding(.top, 40)
        } else if let error = store.searchError {
            ErrorStateView(message: error) { Task { await store.search(env.dataSource) } }
                .frame(minHeight: 220)
        } else if store.didSearch && store.groups.isEmpty {
            Text("No passages found.").font(Typography.body(15)).foregroundStyle(Theme.faint).padding(.top, 30)
        } else {
            ForEach(store.groups) { group in
                CardSurface {
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        Text(group.book).font(Typography.display(18)).foregroundStyle(Theme.inkAccent)
                        ForEach(group.hits) { hit in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    if let heading = hit.heading {
                                        Text(heading).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.accent)
                                    }
                                    if hit.isMedia {
                                        // Whisper chunks carry a page that is an artefact
                                        // of chunking; /library/source is PDF-only, so
                                        // offering to open it could only 404.
                                        Text("video").font(Typography.mono(12)).foregroundStyle(Theme.accent)
                                    } else if let page = hit.page {
                                        Text("p. \(page)").font(Typography.mono(12)).foregroundStyle(Theme.faint)
                                    }
                                }
                                Text(hit.text.prefix(500) + (hit.text.count > 500 ? "…" : ""))
                                    .font(Typography.body(15)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                // Extracted text is a good index and a poor recipe —
                                // a line lost by the text layer is a step never cooked.
                                // Read it in the book instead.
                                if !hit.isMedia, let page = hit.page, let path = hit.sourcePath {
                                    Button {
                                        opening = SourceTarget(title: group.book,
                                                               path: path, page: page)
                                    } label: {
                                        Label("Open page \(page) in the book",
                                              systemImage: "book")
                                            .font(Typography.body(13, weight: .semibold))
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            .padding(.vertical, 4)
                            Divider().overlay(Theme.line)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !(store.status?.ragHealth.ok ?? true) {
                Text("The library index is unreachable — connect to Tailscale and ensure the Atlas stack is running.")
                    .font(Typography.body(14)).foregroundStyle(Theme.faint).padding(.top, 8)
            }
        }
    }
}
