import SwiftUI

/// The running shopping list.
///
/// Quantities are already merged and rendered by the server, so a second recipe
/// adds to a line rather than replacing it. Export is a plain `ShareLink`: the iOS
/// share sheet reaches AnyList, Notes, Reminders and Messages with no per-app
/// integration to break.
struct ShoppingView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var store = ShoppingStore()
    @State private var confirmClear = false
    @State private var selection = Set<ShoppingItem.ID>()
    @State private var editMode: EditMode = .inactive

    var body: some View {
        Group {
            if store.isLoading && store.items.isEmpty {
                LoadingView()
            } else if store.items.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .background(Theme.paper.ignoresSafeArea())
        .navigationTitle("Shopping")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if !store.shareText.isEmpty {
                    ShareLink(item: store.shareText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if !store.items.isEmpty {
                    Button(editMode.isEditing ? "Done" : "Select") {
                        withAnimation {
                            editMode = editMode.isEditing ? .inactive : .active
                            selection = []
                        }
                    }
                }
            }
            ToolbarItem(placement: .secondaryAction) {
                Menu {
                    Button("Clear ticked items") {
                        Task { await store.clear(env.dataSource, checkedOnly: true) }
                    }
                    Button("Clear the whole list", role: .destructive) { confirmClear = true }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Clear the whole list?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear everything", role: .destructive) {
                Task { await store.clear(env.dataSource, checkedOnly: false) }
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("This removes every item, ticked or not. It can't be undone.")
        }
        .task(id: config.useSampleData) { await store.load(env.dataSource) }
        .refreshable { await store.load(env.dataSource) }
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.m) {
            Image(systemName: "cart").font(.system(size: 42)).foregroundStyle(Theme.line)
            Text("Nothing on the list").font(Typography.display(24)).foregroundStyle(Theme.ink)
            Text("Open a recipe, set the servings you're cooking for, then tap “Add to shopping list”. Adding a second recipe adds to what's here rather than replacing it.")
                .font(Typography.body(15))
                .foregroundStyle(Theme.faint)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Space.xl)
    }

    private var list: some View {
        List(selection: $selection) {
            if let error = store.error {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(Typography.body(14)).foregroundStyle(Theme.accent)
                }
            }

            ForEach(store.byAisle) { group in
                Section {
                    ForEach(group.items) { item in row(item) }
                        .onDelete { indexes in
                            let doomed = indexes.map { group.items[$0] }
                            Task { for item in doomed { await store.remove(env.dataSource, item) } }
                        }
                } header: {
                    HStack {
                        Text(group.name)
                        Spacer()
                        if group.id == store.byAisle.first?.id {
                            Text(editMode.isEditing && !selection.isEmpty
                                 ? "\(selection.count) selected"
                                 : "\(store.remaining) left")
                                .font(Typography.mono(12)).foregroundStyle(Theme.faint)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, $editMode)
        .safeAreaInset(edge: .bottom) {
            if editMode.isEditing {
                Button(role: .destructive) {
                    let doomed = selection
                    selection = []
                    Task {
                        await store.removeMany(env.dataSource, doomed)
                        if store.items.isEmpty { editMode = .inactive }
                    }
                } label: {
                    Label(selection.isEmpty ? "Select items to remove"
                                            : "Remove \(selection.count) item\(selection.count == 1 ? "" : "s")",
                          systemImage: "trash")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .disabled(selection.isEmpty)
                .padding(Theme.Space.l)
                .background(.thinMaterial)
            }
        }
    }

    private func row(_ item: ShoppingItem) -> some View {
        Button {
            guard !editMode.isEditing else { return }   // in select mode a tap picks, not ticks
            Task { await store.toggle(env.dataSource, item) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                Image(systemName: item.checked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.checked ? Theme.primary : Theme.line)
                    .font(.system(size: 20))

                Text(item.display)
                    .font(Typography.mono(15, weight: .semibold))
                    .foregroundStyle(item.checked ? Theme.faint : Theme.inkAccent)
                    .frame(minWidth: 74, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.name)
                        .font(Typography.body(16))
                        .foregroundStyle(item.checked ? Theme.faint : Theme.ink)
                        .strikethrough(item.checked, color: Theme.faint)
                    if item.checkGluten {
                        Label("check it's certified GF", systemImage: "exclamationmark.shield")
                            .font(Typography.mono(11))
                            .foregroundStyle(Theme.accent)
                    }
                    if item.recipes.count > 1 {
                        Text("from \(item.recipes.count) recipes")
                            .font(Typography.mono(11)).foregroundStyle(Theme.faint)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .frame(minHeight: Theme.minTouch)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
