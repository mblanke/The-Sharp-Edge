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
    @State private var showImportPicker = false

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(store: store, selection: $selection,
                        showImportPicker: $showImportPicker)
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
        // Gated on setup: loading behind the cover would fire a request at whatever URL
        // happens to be stored, which on a stranger's iPad is the owner's tailnet.
        .task(id: env.generation) {
            guard config.setupComplete else { return }
            await store.load(env.dataSource, gfOnly: config.gfOnly)
        }
        .tint(Theme.primary)
        .onAppear(perform: applyLaunchRoute)
        .fullScreenCover(isPresented: Binding(
            get: { !config.setupComplete },
            set: { _ in }          // no dismiss affordance: a choice has to be made
        )) {
            SetupView()
        }
        // Every arrival route for a .sharpedge file funnels through one confirmation
        // sheet — an import that happens on tap is how people lose recipes.
        .importingRecipes(showPicker: $showImportPicker)
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
            WelcomeDetail(local: config.mode == .local)
        }
    }
}

private struct WelcomeDetail: View {
    /// A device-hosted notebook has no printed cards to scan, so the standard line
    /// would be describing a thing this iPad cannot do.
    var local = false

    var body: some View {
        VStack(spacing: 14) {
            Text("The Sharp Edge")
                .font(Typography.display(40))
                .foregroundStyle(Theme.ink)
            Text(local ? "Your recipes, on this iPad." : "Scan a card, scale the dish, cook.")
                .font(Typography.body(17))
                .foregroundStyle(Theme.faint)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.paper.ignoresSafeArea())
    }
}
