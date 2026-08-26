import SwiftUI

/// Structured editor, in two modes.
///
/// * `.edit` PUTs a new (append-only) version of an existing recipe.
/// * `.create` POSTs a new recipe. The only extra field is the slug — permanent once
///   saved, because QR codes are printed against it (CLAUDE.md §5). It is derived from
///   the title via `/parse/slug`, shown for confirmation, and checked for collision
///   before save so the 409 is a fixable inline warning rather than a dead end.
///
/// Both write routes carry the bearer token; a 401 tells you to set it in Settings.
struct RecipeEditorView: View {
    enum Mode {
        case edit(RecipeFull)
        case create(RecipeCreate)
    }

    let mode: Mode
    var onSaved: (RecipeFull) -> Void

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var slug: String
    @State private var title: String
    @State private var category: String
    @State private var meta: String
    @State private var source: String
    @State private var baseYield: Int
    @State private var yieldWord: String
    @State private var gf: Bool
    @State private var noscale: Bool
    @State private var isDraft: Bool
    @State private var versionLabel: String
    @State private var ingredients: [IngredientRow]
    @State private var steps: [StepRow]
    @State private var notes: [NoteRow]

    @State private var saving = false
    @State private var translating = false
    @State private var errorText: String?
    @State private var showSaveError = false
    @State private var slugEdited = false
    @State private var slugWarning: String?
    @State private var slugTask: Task<Void, Never>?

    // Rows carry their own identity. Ingredient.id and Step.id are derived from their
    // content, so two blank new rows would collide under ForEach($binding) and the
    // second one would be unaddressable — which is exactly what create mode starts with.
    private struct IngredientRow: Identifiable { let id = UUID(); var value: Ingredient }
    private struct StepRow: Identifiable { let id = UUID(); var value: Step }
    private struct NoteRow: Identifiable { let id = UUID(); var value: String }

    private var isCreating: Bool { if case .create = mode { return true }; return false }
    private var existing: RecipeFull? { if case let .edit(r) = mode { return r }; return nil }

    init(mode: Mode, onSaved: @escaping (RecipeFull) -> Void) {
        self.mode = mode
        self.onSaved = onSaved
        switch mode {
        case let .edit(recipe):
            _slug = State(initialValue: recipe.slug)
            _title = State(initialValue: recipe.title)
            _category = State(initialValue: recipe.category)
            _meta = State(initialValue: recipe.meta ?? "")
            _source = State(initialValue: recipe.source ?? "")
            _baseYield = State(initialValue: recipe.baseYield)
            _yieldWord = State(initialValue: recipe.yieldWord)
            _gf = State(initialValue: recipe.gf)
            _noscale = State(initialValue: recipe.noscale)
            _isDraft = State(initialValue: recipe.status == "draft")
            _versionLabel = State(initialValue: "")
            _ingredients = State(initialValue: recipe.currentVersion.ingredients.map { IngredientRow(value: $0) })
            _steps = State(initialValue: recipe.currentVersion.steps.map { StepRow(value: $0) })
            _notes = State(initialValue: recipe.currentVersion.notes.map { NoteRow(value: $0) })
        case let .create(draft):
            _slug = State(initialValue: draft.slug)
            _title = State(initialValue: draft.title)
            _category = State(initialValue: draft.category)
            _meta = State(initialValue: draft.meta ?? "")
            _source = State(initialValue: draft.source ?? "")
            _baseYield = State(initialValue: draft.baseYield)
            _yieldWord = State(initialValue: draft.yieldWord)
            _gf = State(initialValue: draft.gf)
            _noscale = State(initialValue: draft.noscale)
            _isDraft = State(initialValue: draft.status == "draft")
            _versionLabel = State(initialValue: "")
            _ingredients = State(initialValue: draft.ingredients.map { IngredientRow(value: $0) })
            _steps = State(initialValue: draft.steps.map { StepRow(value: $0) })
            _notes = State(initialValue: draft.notes.map { NoteRow(value: $0) })
        }
    }

    /// Convenience for the existing edit call sites.
    init(recipe: RecipeFull, onSaved: @escaping (RecipeFull) -> Void) {
        self.init(mode: .edit(recipe), onSaved: onSaved)
    }

    var body: some View {
        Form {
            // Errors go FIRST. A failed save used to render below the notes section,
            // which on a real recipe is several screens down — so a 401 looked like
            // "Save does nothing" rather than "you have no API token".
            if let errorText {
                Section {
                    Label {
                        Text(errorText).font(Typography.body(14))
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .foregroundStyle(Theme.accent)
                }
            }
            if isCreating { slugSection }
            metadataSection
            ingredientsSection
            stepsSection
            notesSection
        }
        .alert("Couldn't save", isPresented: $showSaveError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "The server rejected the change.")
        }
        .navigationTitle(isCreating ? "New recipe" : "Edit recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            // Deliberately no EditButton here. On a screen titled "Edit recipe" a
            // toolbar button labelled "Edit" reads as "edit the recipe", but it puts
            // the Form into list-edit mode — which makes every TextField read-only.
            // Reordering is done with the per-row arrows instead, as the web form does.
            ToolbarItem(placement: .confirmationAction) {
                if saving {
                    ProgressView()
                } else {
                    Button("Save") { Task { await save() } }.disabled(!canSave)
                }
            }
            // A photographed page keeps the cook's own language; this rewrites it
            // in English for review. The server keeps every amount as it is.
            ToolbarItem(placement: .secondaryAction) {
                if translating {
                    ProgressView()
                } else {
                    Button {
                        Task { await translateToEnglish() }
                    } label: {
                        Label("Translate to English", systemImage: "character.book.closed")
                    }
                    .disabled(saving || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .onAppear { if isCreating && !title.isEmpty { scheduleSlugRefresh() } }
        .onDisappear { slugTask?.cancel() }
    }

    /// Words only — the server carries amounts, units and timers straight through,
    /// so this can never alter a quantity. Lands in the form for review like every
    /// other import; nothing is saved until the cook says so.
    @MainActor
    private func translateToEnglish() async {
        translating = true
        defer { translating = false }
        let body = TranslateRequest(
            target: "en",
            title: title,
            meta: meta.isEmpty ? nil : meta,
            ingredients: ingredients.map(\.value),
            steps: steps.map(\.value),
            notes: notes.map(\.value)
        )
        do {
            let translated = try await env.dataSource.translate(body)
            title = translated.title
            if let m = translated.meta, !m.isEmpty { meta = m }
            ingredients = translated.ingredients.map { IngredientRow(value: $0) }
            steps = translated.steps.map { StepRow(value: $0) }
            notes = translated.notes.map { NoteRow(value: $0) }
            if versionLabel.isEmpty { versionLabel = "translated to English" }
        } catch let error as APIError {
            errorText = error.errorDescription ?? "Could not translate this recipe."
            showSaveError = true
        } catch {
            errorText = "Could not translate this recipe."
            showSaveError = true
        }
    }

    private var canSave: Bool {
        guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        return !isCreating || !slug.isEmpty
    }

    // MARK: - Sections

    private var slugSection: some View {
        Section {
            TextField("slug", text: $slug)
                .font(Typography.mono(15))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: slug) { _, _ in slugEdited = true }
            if let slugWarning {
                Label(slugWarning, systemImage: "exclamationmark.triangle")
                    .font(Typography.body(13))
                    .foregroundStyle(Theme.accent)
            }
        } header: {
            Text("Web address").font(Typography.mono(12, weight: .semibold)).foregroundStyle(Theme.accent)
        } footer: {
            Text("/r/\(slug.isEmpty ? "…" : slug) — permanent once saved. Printed QR codes point at it.")
                .font(Typography.body(12))
        }
    }

    private var metadataSection: some View {
        Section("Recipe") {
            TextField("Title", text: $title)
                .onChange(of: title) { _, _ in if isCreating { scheduleSlugRefresh() } }
            Picker("Category", selection: $category) {
                ForEach(Category.order, id: \.self) { Text($0).tag($0) }
                if !Category.order.contains(category) { Text(category).tag(category) }
            }
            TextField("Meta (one-line note)", text: $meta, axis: .vertical)
            TextField("Source", text: $source)
            Stepper("Base yield: \(baseYield)", value: $baseYield, in: 1...100)
            TextField("Yield word (servings, cups…)", text: $yieldWord)
            Toggle("Gluten-free", isOn: $gf).tint(Theme.primary)
            Toggle("Do not scale (reference)", isOn: $noscale).tint(Theme.primary)
            Toggle("Keep as draft", isOn: $isDraft).tint(Theme.primary)
            if !isCreating {
                TextField("New version label (optional)", text: $versionLabel)
            }
        }
    }

    private var ingredientsSection: some View {
        Section {
            ForEach($ingredients) { $row in
                VStack(spacing: 6) {
                    HStack {
                        TextField("Amount", value: $row.value.amount, format: .number)
                            .keyboardType(.decimalPad).frame(width: 80)
                        Picker("", selection: $row.value.unit) {
                            ForEach(Units.allowed, id: \.self) { Text(Units.label($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                        TextField("Name", text: $row.value.name)
                    }
                    HStack {
                        TextField("Section (optional)", text: Binding(
                            get: { row.value.section ?? "" },
                            set: { row.value.section = $0.isEmpty ? nil : $0 }))
                            .font(Typography.body(13))
                        TextField("Note (optional)", text: Binding(
                            get: { row.value.note ?? "" },
                            set: { row.value.note = $0.isEmpty ? nil : $0 }))
                            .font(Typography.body(13))
                        reorderButtons(id: row.id, in: $ingredients)
                    }
                }
            }
            .onDelete { ingredients.remove(atOffsets: $0) }

            Button { ingredients.append(IngredientRow(value: Ingredient(name: ""))) } label: {
                Label("Add ingredient", systemImage: "plus")
            }
        } header: {
            Text("Ingredients")
        } footer: {
            Text("Amount 0 renders as an em dash — use it for “to taste”. It never scales.")
                .font(Typography.body(12))
        }
    }

    private var stepsSection: some View {
        Section("Method") {
            ForEach($steps) { $row in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Step", text: $row.value.text, axis: .vertical).lineLimit(1...6)
                    HStack {
                        Text("Timer (s)").font(Typography.body(13)).foregroundStyle(Theme.faint)
                        TextField("none", value: Binding(
                            get: { row.value.timerSeconds ?? 0 },
                            set: { row.value.timerSeconds = $0 == 0 ? nil : $0 }), format: .number)
                            .keyboardType(.numberPad).frame(width: 80)
                        Spacer()
                        reorderButtons(id: row.id, in: $steps)
                    }
                }
            }
            .onDelete { steps.remove(atOffsets: $0) }

            Button { steps.append(StepRow(value: Step(text: ""))) } label: {
                Label("Add step", systemImage: "plus")
            }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            ForEach($notes) { $row in
                HStack {
                    TextField("Note", text: $row.value, axis: .vertical)
                    reorderButtons(id: row.id, in: $notes)
                }
            }
            .onDelete { notes.remove(atOffsets: $0) }
            Button { notes.append(NoteRow(value: "")) } label: { Label("Add note", systemImage: "plus") }
        }
    }

    /// Move a row up or down. This is deliberately per-row rather than SwiftUI's
    /// drag-to-reorder, which needs list-edit mode — and edit mode makes every
    /// TextField on the screen read-only. Mirrors the ↑/↓ buttons on the web form.
    private func reorderButtons<T: Identifiable>(id: T.ID, in rows: Binding<[T]>) -> some View {
        HStack(spacing: 2) {
            Button {
                guard let i = rows.wrappedValue.firstIndex(where: { $0.id == id }), i > 0 else { return }
                rows.wrappedValue.swapAt(i, i - 1)
            } label: {
                Image(systemName: "chevron.up").font(.system(size: 12, weight: .semibold))
            }
            .disabled(rows.wrappedValue.firstIndex(where: { $0.id == id }) == 0)
            .accessibilityLabel("Move up")

            Button {
                guard let i = rows.wrappedValue.firstIndex(where: { $0.id == id }),
                      i < rows.wrappedValue.count - 1 else { return }
                rows.wrappedValue.swapAt(i, i + 1)
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 12, weight: .semibold))
            }
            .disabled(rows.wrappedValue.firstIndex(where: { $0.id == id }) == rows.wrappedValue.count - 1)
            .accessibilityLabel("Move down")
        }
        .buttonStyle(.bordered)
        .tint(Theme.primary)
        .labelsHidden()
    }

    // MARK: - Slug

    /// Debounced: the server owns slug generation so web and iOS produce identical
    /// slugs, and it reports collisions before the create POST can 409.
    private func scheduleSlugRefresh() {
        guard isCreating, !slugEdited else { return }
        slugTask?.cancel()
        let probe = title
        slugTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled, !probe.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            guard let result = try? await env.dataSource.slug(for: probe), !Task.isCancelled else { return }
            await MainActor.run {
                slugEdited = false
                slug = result.slug
                slugWarning = result.available ? nil : "That address is already taken — edit it before saving."
            }
        }
    }

    // MARK: - Save

    private func save() async {
        saving = true
        errorText = nil
        let cleanedIngredients = ingredients.map(\.value)
            .filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedSteps = steps.map(\.value)
            .filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedNotes = notes.map(\.value)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let status = isDraft ? "draft" : "active"

        do {
            let saved: RecipeFull
            if let recipe = existing {
                saved = try await env.dataSource.updateRecipe(recipe.slug, RecipeUpdate(
                    title: title, category: category, meta: meta.isEmpty ? nil : meta,
                    baseYield: baseYield, yieldWord: yieldWord, gf: gf, noscale: noscale,
                    source: source.isEmpty ? nil : source, status: status,
                    label: versionLabel.isEmpty ? nil : versionLabel,
                    ingredients: cleanedIngredients, steps: cleanedSteps, notes: cleanedNotes))
            } else {
                saved = try await env.dataSource.createRecipe(RecipeCreate(
                    slug: slug, title: title, category: category, meta: meta.isEmpty ? nil : meta,
                    baseYield: baseYield, yieldWord: yieldWord, gf: gf, noscale: noscale,
                    source: source.isEmpty ? nil : source, status: status, label: nil,
                    ingredients: cleanedIngredients, steps: cleanedSteps, notes: cleanedNotes))
            }
            onSaved(saved)
            dismiss()
        } catch let error as APIError {
            if case let .slugTaken(detail) = error {
                slugWarning = detail
                errorText = "Pick a different web address and save again."
            } else {
                errorText = error.errorDescription
            }
        } catch {
            errorText = error.localizedDescription
        }
        saving = false
    }
}
