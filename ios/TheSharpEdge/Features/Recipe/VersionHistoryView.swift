import SwiftUI

/// Look at a past version and, if you want it back, restore it.
///
/// Every edit appends a version rather than overwriting (CLAUDE.md §6), but until now
/// that history was unreachable: `/versions` returned metadata only and the switcher
/// was inert chips. This is the undo the append-only design was always for.
struct VersionHistoryView: View {
    let slug: String
    let versions: [VersionSummary]
    var onRestored: (RecipeFull) -> Void

    @EnvironmentObject var env: AppEnvironment
    @Environment(\.dismiss) private var dismiss

    @State private var selected: VersionSummary?
    @State private var body_: VersionOut?
    @State private var loading = false
    @State private var restoring = false
    @State private var errorText: String?
    @State private var confirmRestore = false

    var body: some View {
        NavigationStack {
            Group {
                if versions.isEmpty {
                    Text("No earlier versions yet.")
                        .font(Typography.body(15)).foregroundStyle(Theme.faint)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .background(Theme.paper.ignoresSafeArea())
            .navigationTitle("Version history")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
            .task { await pick(versions.last) }
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(versions) { v in
                        Button { Task { await pick(v) } } label: {
                            Chip(text: label(v), selected: v.id == selected?.id)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.vertical, Theme.Space.m)
            }

            Divider()

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.triangle.fill")
                    .font(Typography.body(14)).foregroundStyle(Theme.accent)
                    .padding(Theme.Space.xl)
            }

            if loading {
                LoadingView()
            } else if let b = body_ {
                ScrollView { versionBody(b) }
            }

            Spacer(minLength: 0)

            if let s = selected, !s.isCurrent {
                Button { confirmRestore = true } label: {
                    if restoring {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 50)
                    } else {
                        Label("Restore this version", systemImage: "arrow.uturn.backward")
                            .frame(maxWidth: .infinity, minHeight: 50)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.primaryDeep)
                .disabled(restoring)
                .padding(Theme.Space.l)
            }
        }
        .confirmationDialog("Restore this version?", isPresented: $confirmRestore, titleVisibility: .visible) {
            Button("Restore") { Task { await restore() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This adds it back as a new version. Nothing is deleted, so you can undo the restore too.")
        }
    }

    private func versionBody(_ b: VersionOut) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            SectionHeaderLabel(text: "Ingredients")
            ForEach(b.ingredients) { i in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.m) {
                    Text(ScalingEngine.formatAmount(i.amount, unit: i.unit))
                        .font(Typography.mono(14, weight: .semibold))
                        .foregroundStyle(Theme.inkAccent)
                        .frame(minWidth: 78, alignment: .leading)
                    Text(i.name).font(Typography.body(15)).foregroundStyle(Theme.ink)
                    Spacer(minLength: 0)
                }
            }
            SectionHeaderLabel(text: "Method")
            ForEach(Array(b.steps.enumerated()), id: \.offset) { n, step in
                HStack(alignment: .top, spacing: Theme.Space.m) {
                    Text("\(n + 1)").font(Typography.mono(12)).foregroundStyle(Theme.primary)
                        .frame(width: 20, alignment: .trailing)
                    Text(step.text).font(Typography.body(15)).foregroundStyle(Theme.ink)
                }
            }
            if !b.notes.isEmpty {
                SectionHeaderLabel(text: "Notes")
                ForEach(Array(b.notes.enumerated()), id: \.offset) { _, note in
                    Text(note).font(Typography.body(14)).foregroundStyle(Theme.faint)
                }
            }
        }
        .padding(Theme.Space.xl)
    }

    private func label(_ v: VersionSummary) -> String {
        let base = v.label ?? "v\(v.version)"
        return v.isCurrent ? "\(base) · current" : base
    }

    private func pick(_ v: VersionSummary?) async {
        guard let v else { return }
        selected = v
        loading = true
        errorText = nil
        do {
            body_ = try await env.dataSource.version(slug, v.version)
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        loading = false
    }

    private func restore() async {
        guard let v = selected else { return }
        restoring = true
        errorText = nil
        do {
            onRestored(try await env.dataSource.restoreVersion(slug, v.version))
            dismiss()
        } catch {
            errorText = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
        restoring = false
    }
}
