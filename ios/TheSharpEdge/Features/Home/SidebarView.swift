import SwiftUI

struct SidebarView: View {
    @ObservedObject var store: RecipeListStore
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @Binding var selection: SidebarRoute?

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
                .tint(Theme.green)
            }

            if store.isLoading && store.sections.isEmpty {
                HStack { ProgressView().tint(Theme.green); Text("Loading recipes…").font(Typography.mono(13)).foregroundStyle(Theme.faint) }
            } else if let error = store.error, store.sections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(error).font(Typography.body(14)).foregroundStyle(Theme.faint)
                    Button("Retry") { Task { await store.load(env.dataSource, gfOnly: config.gfOnly) } }
                        .font(Typography.body(14, weight: .semibold))
                }
            }

            ForEach(store.sections) { section in
                Section {
                    ForEach(section.recipes) { recipe in
                        recipeRow(recipe)
                            .tag(SidebarRoute.recipe(recipe.slug))
                    }
                } header: {
                    Text(section.name).font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.copper)
                }
            }

            Section {
                navRow("Library", systemImage: "books.vertical", route: .library)
                navRow("Ask", systemImage: "bubble.left.and.text.bubble.right", route: .ask(nil))
                navRow("Hidden-gluten guide", systemImage: "exclamationmark.shield", route: .glutenGuide)
                navRow("Settings", systemImage: "gearshape", route: .settings)
            } header: {
                Text("Tools").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.copper)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("The Sharp Edge")
        .refreshable { await store.load(env.dataSource, gfOnly: config.gfOnly) }
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
