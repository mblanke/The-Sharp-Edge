import SwiftUI
import UniformTypeIdentifiers

/// One funnel for every way a `.sharpedge` file can arrive.
///
/// There are three — the Files picker, `onOpenURL` (tapping a file, or a mail
/// attachment), and AirDrop, which also lands as `onOpenURL` but from a different
/// directory. Wiring them separately is how one of them ends up untested, and it is
/// always the one somebody actually uses.
@MainActor
final class ImportCoordinator: ObservableObject {
    @Published var plan: ImportService.Plan?
    @Published var error: String?
    @Published var confirmation: String?

    func open(_ url: URL, store: LocalStore) async {
        do {
            plan = try await ImportService.plan(for: url, into: store)
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription
                ?? "Couldn't read that file."
        }
    }

    func finished(_ written: Int) {
        plan = nil
        confirmation = written == 1 ? "1 recipe added" : "\(written) recipes added"
    }
}

/// Attaches every import entry point and the confirmation UI to a view.
struct ImportHandling: ViewModifier {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @StateObject private var coordinator = ImportCoordinator()
    @Binding var showPicker: Bool

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                Task { await coordinator.open(url, store: env.localStore) }
            }
            .fileImporter(isPresented: $showPicker,
                          allowedContentTypes: [.sharpEdgeRecipe, .json],
                          allowsMultipleSelection: false) { result in
                switch result {
                case let .success(urls):
                    guard let url = urls.first else { return }
                    Task { await coordinator.open(url, store: env.localStore) }
                case let .failure(err):
                    coordinator.error = err.localizedDescription
                }
            }
            .sheet(item: Binding(
                get: { coordinator.plan.map(PlanBox.init) },
                set: { if $0 == nil { coordinator.plan = nil } })
            ) { box in
                ImportPlanView(plan: box.plan) { coordinator.finished($0) }
                    .environmentObject(env)
            }
            .alert("Couldn't import", isPresented: Binding(
                get: { coordinator.error != nil },
                set: { if !$0 { coordinator.error = nil } })
            ) {
                Button("OK", role: .cancel) { coordinator.error = nil }
            } message: {
                Text(coordinator.error ?? "")
            }
            .alert("Imported", isPresented: Binding(
                get: { coordinator.confirmation != nil },
                set: { if !$0 { coordinator.confirmation = nil } })
            ) {
                Button("OK", role: .cancel) { coordinator.confirmation = nil }
            } message: {
                Text(coordinator.confirmation ?? "")
            }
    }

    /// `sheet(item:)` needs Identifiable and Plan is a plain value.
    private struct PlanBox: Identifiable {
        let plan: ImportService.Plan
        var id: String { plan.rows.map(\.id).joined(separator: "|") }
    }
}

extension View {
    func importingRecipes(showPicker: Binding<Bool>) -> some View {
        modifier(ImportHandling(showPicker: showPicker))
    }
}
