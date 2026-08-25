import SwiftUI

/// Confirms what an import will do before it does it.
///
/// The sheet exists because the alternative — tapping a `.sharpedge` file and having it
/// land in your notebook immediately — is how people lose recipes. Every row says what
/// will happen and offers the alternatives that make sense for it.
struct ImportPlanView: View {
    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    let plan: ImportService.Plan
    let onDone: (Int) -> Void

    @State private var rows: [ImportService.Row]
    @State private var working = false

    init(plan: ImportService.Plan, onDone: @escaping (Int) -> Void) {
        self.plan = plan
        self.onDone = onDone
        _rows = State(initialValue: plan.rows)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach($rows) { $row in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(row.incoming.title)
                                    .font(Typography.body(16, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Text(row.incoming.category)
                                    .font(Typography.mono(11))
                                    .foregroundStyle(Theme.accent)
                            }

                            if let existing = row.existingTitle {
                                Text("You already have “\(existing)” under this name.")
                                    .font(Typography.body(12))
                                    .foregroundStyle(Theme.faint)
                            }

                            Picker("", selection: $row.resolution) {
                                ForEach(row.options) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)

                            if row.resolution == .rename {
                                Text("Will be saved as \(row.freeSlug)")
                                    .font(Typography.mono(11))
                                    .foregroundStyle(Theme.faint)
                            }
                            if row.resolution == .addVersion {
                                Text("Kept as a new version — the one you have now stays in the history.")
                                    .font(Typography.body(11))
                                    .foregroundStyle(Theme.faint)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                } header: {
                    Text(rows.count == 1 ? "1 recipe" : "\(rows.count) recipes")
                        .font(Typography.mono(12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .navigationTitle("Import recipes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(buttonTitle) { Task { await apply() } }
                        .disabled(working || writeCount == 0)
                        .font(Typography.body(16, weight: .semibold))
                }
            }
        }
    }

    private var writeCount: Int { rows.filter { $0.resolution != .skip }.count }

    private var buttonTitle: String {
        writeCount == 0 ? "Nothing to add" : "Add \(writeCount)"
    }

    private func apply() async {
        working = true
        var edited = plan
        edited.rows = rows
        let written = await ImportService.apply(edited, to: env.localStore)
        env.rebuildDataSource()      // the list has changed underneath every screen
        working = false
        onDone(written)
        dismiss()
    }
}
