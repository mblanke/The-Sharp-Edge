import CoreSpotlight
import SwiftUI

enum SidebarRoute: Hashable {
    case recipe(String)   // slug
    case library
    case shopping
    case plan
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
                    TimerTrayView { timer in selection = .recipe(timer.slug) }
                    detailView
                }
            }
            .environmentObject(store)
        }
        .navigationSplitViewStyle(.balanced)
        // Scale all the way up to the largest accessibility size that still leaves a
        // two-column iPad usable; beyond it the step text is one word per line.
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        // Gated on setup: loading behind the cover would fire a request at whatever URL
        // happens to be stored, which on a stranger's iPad is the owner's tailnet.
        .task(id: env.generation) {
            guard config.setupComplete else { return }
            await store.load(env.dataSource, gfOnly: config.gfOnly)
        }
        .tint(Theme.primary)
        .onAppear(perform: applyLaunchRoute)
        // Spotlight result or a Handoff from another device: straight to the recipe.
        .onContinueUserActivity(CSSearchableItemActionType) { activity in
            if let slug = SpotlightIndex.slug(from: activity) { selection = .recipe(slug) }
        }
        .onContinueUserActivity(SpotlightIndex.activityType) { activity in
            if let slug = SpotlightIndex.slug(from: activity) { selection = .recipe(slug) }
        }
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
        case "plan": selection = .plan
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
        case .plan:
            PlanView(onOpenShopping: { selection = .shopping })
        case let .ask(scope):
            AskView(scopeSlug: scope)
                .id(scope ?? "all")
        case .glutenGuide:
            GlutenGuideView()
        case .settings:
            SettingsView()
        case .none:
            NotebookHome(local: config.mode == .local) { slug in selection = .recipe(slug) }
        }
    }
}

/// What the detail pane shows before a recipe is picked: the notebook as a grid of
/// cards by category. It used to be two lines of text beside a sidebar holding the
/// same recipes, which on a landscape iPad was most of the screen doing nothing.
/// Follows the sidebar's GF toggle and search, since it reads the same sections.
private struct NotebookHome: View {
    /// A device-hosted notebook has no printed cards to scan, so the standard line
    /// would be describing a thing this iPad cannot do.
    var local = false
    var onOpen: (String) -> Void
    @EnvironmentObject private var store: RecipeListStore

    private let columns = [GridItem(.adaptive(minimum: 240, maximum: 360), spacing: Theme.Space.m)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.xl) {
                header
                if store.sections.isEmpty {
                    Text(store.isSearching ? "Nothing in the notebook matches “\(store.query)”."
                                           : "Recipes appear here as the notebook fills.")
                        .font(Typography.body(16))
                        .foregroundStyle(Theme.faint)
                }
                ForEach(store.sections) { section in
                    VStack(alignment: .leading, spacing: Theme.Space.m) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Eyebrow(text: section.name)
                            Text("\(section.recipes.count)")
                                .font(Typography.mono(12)).foregroundStyle(Theme.faint)
                        }
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Space.m) {
                            ForEach(section.recipes) { recipe in
                                Button { onOpen(recipe.slug) } label: { RecipeTile(recipe: recipe) }
                                    .buttonStyle(TileButtonStyle())
                                    .hoverEffect(.lift)
                            }
                        }
                    }
                }
            }
            .padding(Theme.Space.xxl)
            .frame(maxWidth: 1180, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper.ignoresSafeArea())
        .animation(.easeOut(duration: 0.2), value: store.sections.map(\.id))
    }

    private var header: some View {
        let all = store.allCards
        let gf = all.filter(\.gf).count
        return VStack(alignment: .leading, spacing: 6) {
            Text("The Sharp Edge")
                .font(Typography.display(40))
                .foregroundStyle(Theme.ink)
            HStack(spacing: 10) {
                Text(local ? "Your recipes, on this iPad." : "Scan a card, scale the dish, cook.")
                    .font(Typography.body(17))
                    .foregroundStyle(Theme.faint)
                if !all.isEmpty {
                    Text("\(all.count) recipes · \(gf) GF")
                        .font(Typography.mono(12))
                        .foregroundStyle(Theme.faint)
                        .padding(.horizontal, 10).padding(.vertical, 4)
                        .overlay(Capsule().stroke(Theme.line, lineWidth: 1))
                }
            }
        }
    }
}

private struct RecipeTile: View {
    var recipe: RecipeCard

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(recipe.title)
                .font(Typography.display(20))
                .foregroundStyle(Theme.ink)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let meta = recipe.meta, !meta.isEmpty {
                Text(meta)
                    .font(Typography.body(13))
                    .foregroundStyle(Theme.faint)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Theme.Space.s)
            HStack {
                Text(recipe.noscale ? "reference" : "\(recipe.baseYield) \(recipe.yieldWord)")
                    .font(Typography.mono(12))
                    .foregroundStyle(Theme.faint)
                Spacer()
                GFBadge(gf: recipe.gf)
            }
        }
        .padding(Theme.Space.l)
        .padding(.leading, 4)
        .frame(maxWidth: .infinity, minHeight: 132, alignment: .topLeading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .overlay(alignment: .leading) {
            // the notebook's coloured tab
            Capsule().fill(Theme.primary.opacity(0.7)).frame(width: 3).padding(.vertical, Theme.Space.l)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous)
                .stroke(Theme.line, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.lg, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the recipe")
    }
}

/// A tile gives under the finger rather than just flashing.
private struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
