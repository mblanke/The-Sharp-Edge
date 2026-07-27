import SwiftUI

struct RecipeDetailView: View {
    let slug: String
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var listStore: RecipeListStore
    @StateObject private var store = RecipeDetailStore()

    @State private var showCook = false
    @State private var showEdit = false
    @State private var showHistory = false
    @State private var addedToList = false
    @State private var addError: String?
    @StateObject private var shopping = ShoppingStore()
    @State private var checked: Set<String> = []
    var body: some View {
        Group {
            if store.isLoading && store.recipe == nil {
                LoadingView()
            } else if let error = store.error, store.recipe == nil {
                ErrorStateView(message: error) { Task { await store.load(env.dataSource, slug: slug) } }
            } else if let recipe = store.recipe {
                content(recipe)
            } else {
                Color.clear
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                // Available in both modes on purpose: sending somebody a recipe is the
                // point of the format, and the owner is the one with recipes to send.
                // Built from what is already loaded, so it costs nothing and needs no
                // second tap.
                if let recipe = store.recipe {
                    ShareLink(item: NotebookExport.current(recipe),
                              preview: SharePreview(recipe.title,
                                                    image: Image(systemName: "doc.text"))) {
                        Label("Share recipe", systemImage: "square.and.arrow.up")
                    }
                }
            }
        }
        .task(id: env.generation) {
            await store.load(env.dataSource, slug: slug)
            #if DEBUG
            if ProcessInfo.processInfo.environment["UITEST_COOK"] == "1" { showCook = true }
            if ProcessInfo.processInfo.environment["UITEST_HISTORY"] == "1" { showHistory = true }
            #endif
        }
        .fullScreenCover(isPresented: $showCook) {
            if let recipe = store.recipe {
                CookModeView(recipe: recipe, target: store.target)
            }
        }
        .alert("Added to the shopping list", isPresented: $addedToList) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Quantities were added to any lines already there, not replaced.")
        }
        .alert("Couldn't add to the list", isPresented: Binding(
            get: { addError != nil }, set: { if !$0 { addError = nil } })
        ) {
            Button("OK", role: .cancel) { addError = nil }
        } message: {
            Text(addError ?? "")
        }
        .sheet(isPresented: $showHistory) {
            VersionHistoryView(slug: slug, versions: store.versions) { restored in
                store.recipe = restored
                store.target = min(store.maxYield, max(1, store.target))
                Task { await store.load(env.dataSource, slug: slug) }
            }
        }
        .sheet(isPresented: $showEdit) {
            if let recipe = store.recipe {
                NavigationStack {
                    RecipeEditorView(recipe: recipe) { updated in
                        store.recipe = updated
                        // The sidebar keeps its own copy — refresh it, or a renamed
                        // recipe keeps showing its old title in the list.
                        Task { await listStore.load(env.dataSource, gfOnly: config.gfOnly) }
                        store.target = min(store.maxYield, max(1, store.target))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func content(_ recipe: RecipeFull) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header(recipe)

                if !recipe.noscale {
                    CardSurface {
                        VStack(spacing: Theme.Space.m) {
                            ScaleStepper(
                                value: Binding(get: { store.target }, set: { store.setTarget($0) }),
                                unitWord: recipe.yieldWord,
                                minValue: 1, maxValue: store.maxYield, baseValue: recipe.baseYield,
                                onChange: {}
                            )
                            if store.target != recipe.baseYield {
                                Text("scaled from \(recipe.baseYield)")
                                    .font(Typography.mono(12)).foregroundStyle(Theme.faint)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                ingredients
                steps(recipe)
                if !recipe.currentVersion.notes.isEmpty { notes(recipe) }
                if store.versions.count > 1 { VersionSwitcher(versions: store.versions) { showHistory = true } }
                actions(recipe)
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func header(_ recipe: RecipeFull) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Eyebrow(text: recipe.category)
            Text(recipe.title)
                .font(Typography.display(34))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 10) {
                GFBadge(gf: recipe.gf)
                if let meta = recipe.meta, !meta.isEmpty {
                    Text(meta).font(Typography.body(15)).foregroundStyle(Theme.faint)
                }
            }
            if let source = recipe.source, !source.isEmpty {
                Text(source).font(Typography.body(13)).italic().foregroundStyle(Theme.faint)
            }
        }
    }

    private var ingredients: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            Text("Ingredients").font(Typography.display(22)).foregroundStyle(Theme.ink)
            ForEach(store.sections) { section in
                if let name = section.name {
                    SectionHeaderLabel(text: name).padding(.top, 4)
                }
                ForEach(section.rows) { row in
                    ingredientRow(row)
                }
            }
        }
    }

    private func ingredientRow(_ row: ScaledRow) -> some View {
        let isChecked = checked.contains(row.id)
        return Button {
            if isChecked { checked.remove(row.id) } else { checked.insert(row.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                MonoQuantity(text: row.display, flashing: store.flashing)
                    .frame(minWidth: 74, alignment: .leading)
                Text(row.name)
                    .font(Typography.body(16))
                    .foregroundStyle(Theme.ink)
                    .strikethrough(isChecked, color: Theme.faint)
                    .opacity(isChecked ? 0.45 : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 6)
            .frame(minHeight: Theme.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func steps(_ recipe: RecipeFull) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text("Method").font(Typography.display(22)).foregroundStyle(Theme.ink)
            ForEach(Array(recipe.currentVersion.steps.enumerated()), id: \.offset) { idx, step in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Text("\(idx + 1)")
                        .font(Typography.mono(15, weight: .semibold))
                        .foregroundStyle(Theme.offWhite)
                        .frame(width: 28, height: 28)
                        .background(Theme.primary, in: Circle())
                    VStack(alignment: .leading, spacing: 6) {
                        Text(StepText.attributed(step.text))
                            .font(Typography.body(17))
                            .foregroundStyle(Theme.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if let t = step.timerSeconds {
                            Label(timeString(t), systemImage: "timer")
                                .font(Typography.mono(12))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
        }
    }

    private func notes(_ recipe: RecipeFull) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            Text("Notes").font(Typography.display(20)).foregroundStyle(Theme.ink)
            ForEach(Array(recipe.currentVersion.notes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 8) {
                    Text("•").foregroundStyle(Theme.faint)
                    Text(note).font(Typography.body(15)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func actions(_ recipe: RecipeFull) -> some View {
        VStack(spacing: Theme.Space.m) {
            Button { showCook = true } label: { Label("Cook mode", systemImage: "flame") }
                .buttonStyle(PrimaryButtonStyle())

            HStack(spacing: Theme.Space.m) {
                NavigationLink {
                    AskView(scopeSlug: recipe.slug)
                } label: {
                    Label("Ask about this", systemImage: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(SecondaryButtonStyle())

                Button { showEdit = true } label: { Label("Edit", systemImage: "square.and.pencil") }
                    .buttonStyle(SecondaryButtonStyle())
            }

            // Adds the CURRENT scaled quantities, so what lands on the list matches
            // what you're actually cooking. A second recipe adds to existing lines.
            Button {
                Task {
                    if await shopping.add(env.dataSource, slug: recipe.slug, targetYield: store.target) {
                        addedToList = true
                    } else {
                        addError = shopping.error
                    }
                }
            } label: {
                Label("Add to shopping list (\(store.target) \(recipe.yieldWord))",
                      systemImage: "cart.badge.plus")
            }
            .buttonStyle(SecondaryButtonStyle())

            if let url = store.askClaudeURL() {
                Link(destination: url) {
                    Label("Ask Claude (claude.ai)", systemImage: "sparkles")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
        }
        .padding(.top, Theme.Space.s)
    }

    private func timeString(_ seconds: Int) -> String {
        let m = seconds / 60, s = seconds % 60
        if m > 0 && s > 0 { return "\(m) min \(s) s" }
        if m > 0 { return "\(m) min" }
        return "\(s) s"
    }
}

struct VersionSwitcher: View {
    var versions: [VersionSummary]
    /// Tapping opens the history, where a version can be read and restored. These
    /// used to be decoration — there was no endpoint behind them to switch to.
    var onOpen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text("Versions").font(Typography.display(20)).foregroundStyle(Theme.ink)
                Spacer()
                Button("History", action: onOpen).font(Typography.body(14, weight: .semibold))
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(versions) { v in
                        Button(action: onOpen) {
                            Chip(text: v.label ?? "v\(v.version)", selected: v.isCurrent)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}
