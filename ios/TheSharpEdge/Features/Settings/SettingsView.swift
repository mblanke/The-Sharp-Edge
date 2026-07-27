import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig

    @State private var urlField: String = ""
    @State private var tokenField: String = ""
    @State private var tokenState: TokenState = .unknown

    enum TokenState { case unknown, missing, valid, rejected }
    @State private var health: HealthState = .unknown
    @State private var checking = false

    enum HealthState { case unknown, ok, ragOk, down(String) }

    @State private var pendingMode: AppMode?

    var body: some View {
        Form {
            Section("Notebook") {
                HStack {
                    Text(config.mode.title).font(Typography.body(15))
                    Spacer()
                    Button("Change") { pendingMode = config.mode == .local ? .server : .local }
                        .font(Typography.body(14))
                }
                Text(config.mode.blurb)
                    .font(Typography.body(12)).foregroundStyle(Theme.faint)
            }

            if config.mode == .server {
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
                HStack {
                    Text("Stored").font(Typography.body(13)).foregroundStyle(Theme.faint)
                    Spacer()
                    if config.token.isEmpty {
                        Label("nothing saved", systemImage: "xmark.circle")
                            .font(Typography.mono(12)).foregroundStyle(Theme.accent)
                    } else {
                        Label("\(config.token.count) chars, ends \(String(config.token.suffix(4)))",
                              systemImage: "checkmark.circle.fill")
                            .font(Typography.mono(12)).foregroundStyle(Theme.primary)
                    }
                }
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
                switch tokenState {
                case .unknown: EmptyView()
                case .missing:
                    Label("No token saved — reads work, saving will fail", systemImage: "xmark.circle.fill")
                        .font(Typography.mono(12)).foregroundStyle(Theme.accent)
                case .rejected:
                    Label("Token rejected by the server", systemImage: "xmark.circle.fill")
                        .font(Typography.mono(12)).foregroundStyle(Theme.accent)
                case .valid:
                    Label("Token accepted — saving will work", systemImage: "checkmark.circle.fill")
                        .font(Typography.mono(12)).foregroundStyle(Theme.primary)
                }
            }
            }   // if mode == .server

            #if DEBUG
            Section("Developer") {
                Toggle("Use sample data (offline)", isOn: Binding(
                    get: { config.useSampleData },
                    set: { config.useSampleData = $0; env.rebuildDataSource() }
                )).tint(Theme.primary)
                Text("Mode chosen by: \(config.modeOrigin)")
                    .font(Typography.mono(11)).foregroundStyle(Theme.faint)
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
        .alert("Switch notebook?", isPresented: Binding(
            get: { pendingMode != nil },
            set: { if !$0 { pendingMode = nil } })
        ) {
            Button("Cancel", role: .cancel) { pendingMode = nil }
            Button("Switch") {
                if let target = pendingMode {
                    config.mode = target
                    config.setupComplete = true
                    env.rebuildDataSource()
                }
                pendingMode = nil
            }
        } message: {
            // Say plainly what does not happen. "Switch" sounds reversible and is —
            // but somebody expecting their recipes to come along would be badly surprised.
            Text(pendingMode == .local
                 ? "This iPad will show its own notebook, which starts empty. Nothing is copied from the server, and nothing you add here syncs back. Your server recipes are untouched — switch back any time."
                 : "This iPad will show recipes from your server. The notebook on this device stays exactly as it is, and is still here if you switch back. Nothing is copied either way.")
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
        config.baseURLString = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        config.token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        // Rebuild synchronously. This used to ride on a 150 ms debounce, so anything
        // reading env.dataSource on the next line — "Test connection", notably — was
        // talking to the *previous* server with the *previous* token.
        env.rebuildDataSource()
    }

    /// Tests what actually matters, against the values currently in the fields.
    ///
    /// This used to `commit()` and then read `env.dataSource` on the next line — which
    /// was rebuilt on a 150 ms debounce, so it tested the *previous* server with the
    /// *previous* token. `ServerProbe` builds a throwaway client from the typed values,
    /// so the answer is about what you just typed. It also checks the host is a Sharp
    /// Edge server at all, and reports the token separately from reachability, because
    /// `/healthz` needs no token and a green tick from it says nothing about saving.
    private func checkHealth() async {
        checking = true
        health = .unknown
        tokenState = .unknown
        defer { checking = false }

        let typedURL = urlField.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedToken = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: typedURL) else {
            health = .down("that doesn't look like a URL")
            return
        }

        switch await ServerProbe.check(url: url, token: typedToken) {
        case let .ok(_, token):
            health = .ok
            switch token {
            case .none: tokenState = .missing
            case .accepted: tokenState = .valid
            case .rejected: tokenState = .rejected
            }
            // Only persist settings that have been shown to work.
            commit()
            // The index is a separate question from "is the server up".
            if let status = try? await env.dataSource.libraryStatus(), status.ragHealth.ok {
                health = .ragOk
            }
        case let .unreachable(why):
            health = .down(why)
        case .notSharpEdge:
            health = .down("answered, but isn't a Sharp Edge server")
        }
    }
}
