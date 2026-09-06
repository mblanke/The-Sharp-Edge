import SwiftUI

/// The week: seven days, three meals, a recipe in a slot. Feeds the running shopping
/// list — the same one the web and the phone share — with one tap.
struct PlanView: View {
    var onOpenShopping: () -> Void = {}
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var listStore: RecipeListStore
    @StateObject private var store = PlanStore()

    /// The slot the picker is open for.
    @State private var picking: (date: String, meal: Meal)?
    @State private var pickerQuery = ""
    @State private var undo: PlanEntry?
    @State private var pushed = false

    var body: some View {
        Group {
            if store.isLoading && store.plan.entries.isEmpty && store.error == nil {
                LoadingView()
            } else if let error = store.error, store.plan.entries.isEmpty {
                ErrorStateView(message: error) { Task { await store.load(env.dataSource) } }
            } else {
                week
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Meal plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        if await store.pushToShopping(env.dataSource) { pushed = true }
                    }
                } label: {
                    if store.pushing {
                        ProgressView()
                    } else {
                        Label("Add week to list", systemImage: "cart.badge.plus")
                    }
                }
                .disabled(store.plan.entries.isEmpty || store.pushing)
            }
        }
        .task(id: env.generation) { await store.load(env.dataSource) }
        .refreshable { await store.load(env.dataSource) }
        .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
            picker
        }
        .alert("The week is on the list", isPresented: $pushed) {
            Button("Open the list") { onOpenShopping() }
            Button("Stay here", role: .cancel) {}
        } message: {
            Text("Every planned recipe was added at its servings. Quantities merge into lines already there.")
        }
    }

    // MARK: week grid

    private var week: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                header
                if let error = store.error {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(Typography.body(14)).foregroundStyle(Theme.accent)
                        Spacer()
                        Button("Try again") { Task { await store.load(env.dataSource) } }
                            .font(Typography.body(14, weight: .semibold)).foregroundStyle(Theme.inkAccent)
                    }
                }
                if let undo {
                    HStack {
                        Text("Removed \(undo.recipeTitle)").font(Typography.body(14)).foregroundStyle(Theme.faint)
                        Spacer()
                        Button("Undo") {
                            Task { await store.restore(env.dataSource, undo) }
                            self.undo = nil
                        }
                        .font(Typography.body(14, weight: .semibold)).foregroundStyle(Theme.inkAccent)
                    }
                    .padding(Theme.Space.m)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                }
                ForEach(store.days, id: \.self) { day in
                    dayCard(day)
                }
                if store.plan.entries.isEmpty {
                    Text("Tap a meal to put a recipe on it. “Add week to list” then sends everything to the shopping list at the servings you chose.")
                        .font(Typography.body(14)).foregroundStyle(Theme.faint)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.Space.xl)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        HStack(spacing: Theme.Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Eyebrow(text: "Week of")
                Text(PlanWeek.label(store.week))
                    .font(Typography.display(28)).foregroundStyle(Theme.ink)
            }
            Spacer()
            Button { Task { await store.shift(env.dataSource, by: -1) } } label: {
                Image(systemName: "chevron.left").frame(width: Theme.minTouch, height: Theme.minTouch)
            }
            .accessibilityLabel("Previous week")
            Button("Today") { Task { await store.today(env.dataSource) } }
                .font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.inkAccent)
            Button { Task { await store.shift(env.dataSource, by: 1) } } label: {
                Image(systemName: "chevron.right").frame(width: Theme.minTouch, height: Theme.minTouch)
            }
            .accessibilityLabel("Next week")
        }
        .disabled(store.isLoading)
    }

    private func dayCard(_ day: String) -> some View {
        CardSurface {
            VStack(alignment: .leading, spacing: Theme.Space.s) {
                HStack {
                    Text(PlanWeek.label(day))
                        .font(Typography.mono(12, weight: .semibold))
                        .foregroundStyle(PlanWeek.isToday(day) ? Theme.accent : Theme.primary)
                    if PlanWeek.isToday(day) {
                        Text("today").font(Typography.mono(11)).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }
                ForEach(Meal.allCases) { meal in
                    slot(day, meal)
                }
                if store.entries(on: day).isEmpty && store.pendingSlot == nil {
                    Button("more meals…") {
                        pickerQuery = ""
                        picking = (day, .breakfast)
                    }
                    .font(Typography.mono(11)).foregroundStyle(Theme.faint)
                    .frame(minHeight: 32)
                }
            }
        }
    }

    @ViewBuilder
    private func slot(_ day: String, _ meal: Meal) -> some View {
        let key = "\(day):\(meal.rawValue)"
        if let entry = store.entry(day, meal) {
            HStack(spacing: Theme.Space.m) {
                Text(meal.label).font(Typography.mono(11)).foregroundStyle(Theme.faint)
                    .frame(width: 72, alignment: .leading)
                Text(entry.recipeTitle).font(Typography.body(15)).foregroundStyle(Theme.ink).lineLimit(1)
                Spacer()
                Text("×\(entry.scaledYield)").font(Typography.mono(12)).foregroundStyle(Theme.faint)
                GFBadge(gf: entry.gf)
                Button {
                    undo = entry
                    Task { await store.remove(env.dataSource, entry) }
                } label: {
                    Image(systemName: "xmark").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: Theme.minTouch, height: Theme.minTouch)
                }
                .accessibilityLabel("Remove \(entry.recipeTitle) from \(meal.label)")
            }
            .frame(minHeight: Theme.minTouch)
        } else if store.pendingSlot == key {
            HStack(spacing: Theme.Space.m) {
                Text(meal.label).font(Typography.mono(11)).foregroundStyle(Theme.faint)
                    .frame(width: 72, alignment: .leading)
                ProgressView().controlSize(.small)
                Text("adding…").font(Typography.body(14)).foregroundStyle(Theme.faint)
                Spacer()
            }
            .frame(minHeight: Theme.minTouch)
        } else if meal == .dinner || !store.entries(on: day).isEmpty {
            Button {
                pickerQuery = ""
                picking = (day, meal)
            } label: {
                HStack(spacing: Theme.Space.m) {
                    Text(meal.label).font(Typography.mono(11)).foregroundStyle(Theme.faint)
                        .frame(width: 72, alignment: .leading)
                    Label("Add", systemImage: "plus").font(Typography.body(14)).foregroundStyle(Theme.inkAccent)
                    Spacer()
                }
                .frame(minHeight: Theme.minTouch)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Add a recipe to \(meal.label) on \(PlanWeek.label(day))")
        }
    }

    // MARK: picker

    private var pickable: [RecipeCard] {
        let q = pickerQuery.trimmingCharacters(in: .whitespaces).lowercased()
        return listStore.allCards
            .filter { !$0.noscale }
            .filter { q.isEmpty || $0.title.lowercased().contains(q) }
    }

    private var picker: some View {
        NavigationStack {
            List {
                if pickable.isEmpty {
                    ContentUnavailableView.search(text: pickerQuery)
                }
                ForEach(pickable) { card in
                    Button {
                        guard let slot = picking else { return }
                        picking = nil
                        Task {
                            if !(await store.add(env.dataSource, date: slot.date, meal: slot.meal, recipe: card)) {
                                picking = slot
                            }
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(card.title).font(Typography.body(16)).foregroundStyle(Theme.ink)
                                if let meta = card.meta, !meta.isEmpty {
                                    Text(meta).font(Typography.body(12)).foregroundStyle(Theme.faint).lineLimit(1)
                                }
                            }
                            Spacer()
                            GFBadge(gf: card.gf)
                        }
                        .frame(minHeight: Theme.minTouch)
                    }
                }
            }
            .searchable(text: $pickerQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "Find a recipe")
            .navigationTitle(picking.map { "\($0.meal.label) · \(PlanWeek.label($0.date))" } ?? "Add")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { picking = nil } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
