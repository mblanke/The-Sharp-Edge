import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig

    @State private var urlField: String = ""
    @State private var tokenField: String = ""
    @State private var health: HealthState = .unknown
    @State private var checking = false

    enum HealthState { case unknown, ok, ragOk, down(String) }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Base URL", text: $urlField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(Typography.mono(15))
                Text("Your recipe server over Tailscale, e.g. \(AppConfig.defaultBaseURL)")
                    .font(Typography.body(12)).foregroundStyle(Theme.faint)
                Button("Use default (\(AppConfig.defaultBaseURL))") { urlField = AppConfig.defaultBaseURL }
                    .font(Typography.body(13))
            }

            Section("API token") {
                SecureField("Bearer token (for editing)", text: $tokenField)
                    .font(Typography.mono(15))
                Text("Only needed to save recipe edits. Reads, scaling, Ask and search need no token.")
                    .font(Typography.body(12)).foregroundStyle(Theme.faint)
            }

            Section("Connection") {
                Button {
                    Task { await checkHealth() }
                } label: {
                    HStack {
                        Text("Test connection")
                        Spacer()
                        if checking { ProgressView() } else { healthBadge }
                    }
                }
            }

            #if DEBUG
            Section("Developer") {
                Toggle("Use sample data (offline)", isOn: Binding(
                    get: { config.useSampleData },
                    set: { config.useSampleData = $0 }
                )).tint(Theme.primary)
                Text("When on, the app renders bundled fixtures instead of the network.")
                    .font(Typography.body(12)).foregroundStyle(Theme.faint)
            }
            #endif

            Section {
                Button("Save settings") { commit() }
                    .font(Typography.body(16, weight: .semibold))
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            urlField = config.baseURLString
            tokenField = config.token
        }
    }

    @ViewBuilder
    private var healthBadge: some View {
        switch health {
        case .unknown: EmptyView()
        case .ok: Label("API ok", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.primary).font(Typography.mono(13))
        case .ragOk: Label("API + index ok", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.primary).font(Typography.mono(13))
        case let .down(msg): Label(msg, systemImage: "xmark.circle.fill").foregroundStyle(Theme.accent).font(Typography.mono(13))
        }
    }

    private func commit() {
        config.baseURLString = urlField.trimmingCharacters(in: .whitespaces)
        config.token = tokenField.trimmingCharacters(in: .whitespaces)
    }

    private func checkHealth() async {
        commit()
        checking = true
        health = .unknown
        let source = env.dataSource
        do {
            let ok = try await source.health()
            if ok {
                if let status = try? await source.libraryStatus(), status.ragHealth.ok {
                    health = .ragOk
                } else {
                    health = .ok
                }
            } else {
                health = .down("no response")
            }
        } catch {
            health = .down((error as? APIError)?.errorDescription ?? "unreachable")
        }
        checking = false
    }
}
