import SwiftUI

struct LibraryView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var store = LibraryStore()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                searchBar
                results
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 820)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Library")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: config.useSampleData) {
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
                                    if let page = hit.page {
                                        Text("p. \(page)").font(Typography.mono(12)).foregroundStyle(Theme.faint)
                                    }
                                }
                                Text(hit.text.prefix(500) + (hit.text.count > 500 ? "…" : ""))
                                    .font(Typography.body(15)).foregroundStyle(Theme.ink)
                                    .fixedSize(horizontal: false, vertical: true)
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
