import SwiftUI

/// Structured editor. Saving PUTs a new (append-only) version with the bearer token.
struct RecipeEditorView: View {
    let recipe: RecipeFull
    var onSaved: (RecipeFull) -> Void

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var category: String
    @State private var meta: String
    @State private var source: String
    @State private var baseYield: Int
    @State private var yieldWord: String
    @State private var gf: Bool
    @State private var noscale: Bool
    @State private var versionLabel: String
    @State private var ingredients: [Ingredient]
    @State private var steps: [Step]
    @State private var notes: [String]

    @State private var saving = false
    @State private var errorText: String?

    init(recipe: RecipeFull, onSaved: @escaping (RecipeFull) -> Void) {
        self.recipe = recipe
        self.onSaved = onSaved
        _title = State(initialValue: recipe.title)
        _category = State(initialValue: recipe.category)
        _meta = State(initialValue: recipe.meta ?? "")
        _source = State(initialValue: recipe.source ?? "")
        _baseYield = State(initialValue: recipe.baseYield)
        _yieldWord = State(initialValue: recipe.yieldWord)
        _gf = State(initialValue: recipe.gf)
        _noscale = State(initialValue: recipe.noscale)
        _versionLabel = State(initialValue: "")
        _ingredients = State(initialValue: recipe.currentVersion.ingredients)
        _steps = State(initialValue: recipe.currentVersion.steps)
        _notes = State(initialValue: recipe.currentVersion.notes)
    }

    var body: some View {
        Form {
            metadataSection
            ingredientsSection
            stepsSection
            notesSection
            if let errorText { Section { Text(errorText).foregroundStyle(Theme.copper).font(Typography.body(14)) } }
        }
        .navigationTitle("Edit recipe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                if saving { ProgressView() } else { Button("Save") { Task { await save() } } }
            }
        }
    }

    private var metadataSection: some View {
        Section("Recipe") {
            TextField("Title", text: $title)
            Picker("Category", selection: $category) {
                ForEach(Category.order, id: \.self) { Text($0).tag($0) }
                if !Category.order.contains(category) { Text(category).tag(category) }
            }
            TextField("Meta (one-line note)", text: $meta, axis: .vertical)
            TextField("Source", text: $source)
            Stepper("Base yield: \(baseYield)", value: $baseYield, in: 1...100)
            TextField("Yield word (servings, cups…)", text: $yieldWord)
            Toggle("Gluten-free", isOn: $gf).tint(Theme.green)
            Toggle("Do not scale (reference)", isOn: $noscale).tint(Theme.green)
            TextField("New version label (optional)", text: $versionLabel)
        }
    }

    private var ingredientsSection: some View {
        Section("Ingredients") {
            ForEach($ingredients) { $ing in
                VStack(spacing: 6) {
                    HStack {
                        TextField("Amount", value: $ing.amount, format: .number)
                            .keyboardType(.decimalPad).frame(width: 80)
                        Picker("", selection: $ing.unit) {
                            ForEach(Units.allowed, id: \.self) { Text(Units.label($0)).tag($0) }
                        }
                        .labelsHidden().frame(width: 90)
                        TextField("Name", text: $ing.name)
                    }
                    HStack {
                        TextField("Section (optional)", text: Binding(get: { ing.section ?? "" }, set: { ing.section = $0.isEmpty ? nil : $0 }))
                            .font(Typography.body(13))
                        TextField("Note (optional)", text: Binding(get: { ing.note ?? "" }, set: { ing.note = $0.isEmpty ? nil : $0 }))
                            .font(Typography.body(13))
                    }
                }
            }
            .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { ingredients.remove(atOffsets: $0) }

            Button { ingredients.append(Ingredient(name: "")) } label: { Label("Add ingredient", systemImage: "plus") }
        }
    }

    private var stepsSection: some View {
        Section("Method") {
            ForEach($steps) { $step in
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Step", text: $step.text, axis: .vertical).lineLimit(1...6)
                    HStack {
                        Text("Timer (s)").font(Typography.body(13)).foregroundStyle(Theme.faint)
                        TextField("none", value: Binding(get: { step.timerSeconds ?? 0 }, set: { step.timerSeconds = $0 == 0 ? nil : $0 }), format: .number)
                            .keyboardType(.numberPad).frame(width: 80)
                    }
                }
            }
            .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { steps.remove(atOffsets: $0) }

            Button { steps.append(Step(text: "")) } label: { Label("Add step", systemImage: "plus") }
        }
    }

    private var notesSection: some View {
        Section("Notes") {
            ForEach(notes.indices, id: \.self) { i in
                TextField("Note", text: Binding(get: { notes[i] }, set: { notes[i] = $0 }), axis: .vertical)
            }
            .onDelete { notes.remove(atOffsets: $0) }
            Button { notes.append("") } label: { Label("Add note", systemImage: "plus") }
        }
    }

    private func save() async {
        saving = true
        errorText = nil
        let cleanedIngredients = ingredients.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedSteps = steps.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        let cleanedNotes = notes.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let payload = RecipeUpdate(
            title: title, category: category, meta: meta.isEmpty ? nil : meta,
            baseYield: baseYield, yieldWord: yieldWord, gf: gf, noscale: noscale,
            source: source.isEmpty ? nil : source, status: recipe.status,
            label: versionLabel.isEmpty ? nil : versionLabel,
            ingredients: cleanedIngredients, steps: cleanedSteps, notes: cleanedNotes)
        do {
            let updated = try await env.dataSource.updateRecipe(recipe.slug, payload)
            onSaved(updated)
            dismiss()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        saving = false
    }
}
