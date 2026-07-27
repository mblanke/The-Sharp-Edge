import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RecipeListStore
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @Binding var selection: SidebarRoute?

    @State private var showCapture = false
    @State private var draft: RecipeCreate?

    var body: some View {
        List(selection: $selection) {
            Section {
                Toggle(isOn: Binding(
                    get: { config.gfOnly },
                    set: { config.gfOnly = $0; store.applyFilter(gfOnly: $0) }
                )) {
                    Label("Gluten-free only", systemImage: "leaf")
                        .font(Typography.body(15, weight: .semibold))
                }
                .tint(Theme.primary)
            }

            if store.isLoading && store.sections.isEmpty {
                HStack { ProgressView().tint(Theme.primary); Text("Loading recipes…").font(Typography.mono(13)).foregroundStyle(Theme.faint) }
            } else if let error = store.error, store.sections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(Typography.body(14)).foregroundStyle(Theme.faint)
                    Button("Retry") { Task { await store.load(env.dataSource, gfOnly: config.gfOnly) } }
                        .font(Typography.body(14, weight: .semibold))
                }
            } else if store.sections.isEmpty {
                // A device-hosted notebook starts empty, and an empty sidebar with no
                // explanation is exactly the poor greeting the setup screen exists to
                // avoid. Say where recipes come from rather than showing nothing.
                VStack(alignment: .leading, spacing: 10) {
                    Text(config.mode == .local ? "No recipes yet" : "No recipes here yet")
                        .font(Typography.body(16, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(config.mode == .local
                         ? "This iPad keeps its own notebook. Add your first recipe with ＋ above — type it in, or dictate it in English, French, German or Romanian."
                         : "The server has no active recipes to show.")
                        .font(Typography.body(13))
                        .foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                    if config.mode == .local {
                        Button { draft = RecipeCreate() } label: {
                            Label("Add a recipe", systemImage: "square.and.pencil")
                                .font(Typography.body(14, weight: .semibold))
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            ForEach(store.sections) { section in
                Section {
                    ForEach(section.recipes) { recipe in
                        recipeRow(recipe)
                            .tag(SidebarRoute.recipe(recipe.slug))
                    }
                } header: {
                    Text(section.name).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.accent)
                }
            }

            Section {
                navRow("Shopping list", systemImage: "cart", route: .shopping)
                // Absent rather than disabled on a device-hosted notebook. These read
                // the owner's private cookbook corpus, which is not part of what gets
                // shared (CLAUDE.md §1) — and a greyed-out row advertises it.
                if config.hasLibrary {
                    navRow("Library", systemImage: "books.vertical", route: .library)
                    navRow("Ask", systemImage: "bubble.left.and.text.bubble.right", route: .ask(nil))
                }
                navRow("Hidden-gluten guide", systemImage: "exclamationmark.shield", route: .glutenGuide)
                navRow("Settings", systemImage: "gearshape", route: .settings)
            } header: {
                Text("Tools").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.accent)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("The Sharp Edge")
        .refreshable { await store.load(env.dataSource, gfOnly: config.gfOnly) }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { draft = RecipeCreate() } label: {
                        Label("Type it in", systemImage: "square.and.pencil")
                    }
                    Button { showCapture = true } label: {
                        Label("Dictate it", systemImage: "mic")
                    }
                } label: {
                    Label("Add recipe", systemImage: "plus")
                }
            }
        }
        .onAppear {
            #if DEBUG
            // Screenshot hook, same idea as RootView's UITEST_ROUTE.
            switch ProcessInfo.processInfo.environment["UITEST_SHEET"] {
            case "capture": showCapture = true
            case "create": draft = RecipeCreate()
            case "create-filled":
                draft = RecipeCreate(
                    slug: "screenshot-probe", title: "Screenshot Probe", category: "Pasta",
                    ingredients: [Ingredient(amount: 2, unit: "tbsp", name: "olive oil"),
                                  Ingredient(amount: 500, unit: "g", name: "San Marzano tomatoes"),
                                  Ingredient(amount: 0, unit: "", name: "salt")],
                    steps: [Step(text: "Sweat the aromatics."), Step(text: "Simmer 40 minutes.")],
                    notes: ["Better the next day."])
            default: break
            }
            #endif
        }
        .sheet(isPresented: $showCapture) {
            VoiceCaptureView { captured in
                showCapture = false
                // Dictation is never 100% right, so it always lands on the editable
                // form rather than saving straight through.
                draft = captured
            }
        }
        .sheet(item: $draft) { newDraft in
            NavigationStack {
                RecipeEditorView(mode: .create(newDraft)) { saved in
                    Task { await store.load(env.dataSource, gfOnly: config.gfOnly) }
                    selection = .recipe(saved.slug)
                }
            }
        }
    }

    private func recipeRow(_ recipe: RecipeCard) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title)
                    .font(Typography.body(16, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                if let meta = recipe.meta, !meta.isEmpty {
                    Text(meta)
                        .font(Typography.body(12))
                        .foregroundStyle(Theme.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            GFBadge(gf: recipe.gf)
        }
        .padding(.vertical, 4)
        .frame(minHeight: Theme.minTouch)
    }

    private func navRow(_ title: String, systemImage: String, route: SidebarRoute) -> some View {
        Label(title, systemImage: systemImage)
            .font(Typography.body(15, weight: .medium))
            .frame(minHeight: Theme.minTouch)
            .tag(route)
    }
}
