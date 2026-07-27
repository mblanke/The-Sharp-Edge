import SwiftUI

enum SidebarRoute: Hashable {
    case recipe(String)   // slug
    case library
    case shopping
    case ask(String?)     // optional recipe scope slug
    case glutenGuide
    case settings
}

struct RootView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var store = RecipeListStore()

    @State private var selection: SidebarRoute?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, selection: $selection)
                .navigationSplitViewColumnWidth(min: 300, ideal: 340, max: 420)
        } detail: {
            NavigationStack {
                VStack(spacing: 0) {
                    OfflineBanner()
                    detailView
                }
            }
            .environmentObject(store)
        }
        .navigationSplitViewStyle(.balanced)
        .task(id: env.generation) { await store.load(env.dataSource, gfOnly: config.gfOnly) }
        .tint(Theme.primary)
        .onAppear(perform: applyLaunchRoute)
    }

    /// DEBUG-only: allow screenshots/tests to open a specific screen via an env var.
    private func applyLaunchRoute() {
        #if DEBUG
        guard selection == nil,
              let route = ProcessInfo.processInfo.environment["UITEST_ROUTE"] else { return }
        switch route {
        case "library": selection = .library
        case "shopping": selection = .shopping
        case "ask": selection = .ask(nil)
        case "gluten": selection = .glutenGuide
        case "settings": selection = .settings
        default: selection = .recipe(route)   // treat as a slug
        }
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case let .recipe(slug):
            RecipeDetailView(slug: slug)
                .id(slug)
        case .library:
            LibraryView()
        case .shopping:
            ShoppingView()
        case let .ask(scope):
            AskView(scopeSlug: scope)
                .id(scope ?? "all")
        case .glutenGuide:
            GlutenGuideView()
        case .settings:
            SettingsView()
        case .none:
            WelcomeDetail()
        }
    }
}

private struct WelcomeDetail: View {
    var body: some View {
        VStack(spacing: 14) {
            Text("The Sharp Edge")
                .font(Typography.display(40))
                .foregroundStyle(Theme.ink)
            Text("Scan a card, scale the dish, cook.")
                .font(Typography.body(17))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}
