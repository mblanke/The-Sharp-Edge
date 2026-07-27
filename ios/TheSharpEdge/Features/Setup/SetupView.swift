import SwiftUI

/// First run. Shown once, only on a device with no trace of prior use.
///
/// Before this, a fresh install dropped straight into the recipe list pointed at the
/// owner's private Tailscale address. For the owner that worked. For anybody else it
/// showed an empty sidebar with a raw network error and no hint that Settings existed —
/// which is a poor greeting for someone who was handed the app to keep their own recipes.
struct SetupView: View {
    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig

    @State private var page: Page = .choose
    @State private var urlField = AppConfig.defaultBaseURL
    @State private var tokenField = ""
    @State private var probing = false
    @State private var result: ServerProbe.Result?

    private enum Page { case choose, server }

    var body: some View {
        NavigationStack {
            Group {
                switch page {
                case .choose: chooser
                case .server: serverForm
                }
            }
            .background(Theme.paper.ignoresSafeArea())
        }
    }

    // MARK: - Chooser

    private var chooser: some View {
        // Centred vertically rather than pinned to the top: on a 13" iPad the content is
        // barely a third of the screen, and top-aligning it leaves a page of dead space
        // under two buttons. The GeometryReader keeps it scrollable anyway, so large
        // accessibility text still reaches the second card.
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("The Sharp Edge")
                            .font(Typography.display(36))
                            .foregroundStyle(Theme.ink)
                        Text("Where should this iPad keep its recipes?")
                            .font(Typography.body(17))
                            .foregroundStyle(Theme.faint)
                    }
                    .padding(.bottom, 4)

                    card(.local) {
                        config.mode = .local
                        config.setupComplete = true
                        env.rebuildDataSource()
                    }

                    card(.server) { page = .server }

                    Text("You can change this later in Settings. Nothing is copied between the two — each keeps its own recipes.")
                        .font(Typography.body(12))
                        .foregroundStyle(Theme.faint)
                        .padding(.top, 2)
                }
                .padding(28)
                .frame(maxWidth: 620)
                .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .center)
            }
        }
    }

    private func card(_ mode: AppMode, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: mode == .local ? "ipad" : "server.rack")
                        .font(.system(size: 20))
                        .foregroundStyle(Theme.primary)
                    Text(mode.title)
                        .font(Typography.body(18, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.faint)
                }
                Text(mode.blurb)
                    .font(Typography.body(14))
                    .foregroundStyle(Theme.faint)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server

    private var serverForm: some View {
        Form {
            Section("Server address") {
                TextField("https://…", text: $urlField)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .font(Typography.mono(15))
            }

            Section("API token") {
                SecureField("Bearer token", text: $tokenField)
                    .font(Typography.mono(15))
                Text("Optional. Reading, scaling and the shopping list work without one; saving edits needs it.")
                    .font(Typography.body(12)).foregroundStyle(Theme.faint)
            }

            Section {
                Button {
                    Task { await probe() }
                } label: {
                    HStack {
                        Text("Connect").font(Typography.body(16, weight: .semibold))
                        Spacer()
                        if probing { ProgressView() }
                    }
                }
                .disabled(probing || URL(string: urlField) == nil)

                if let result { resultRow(result) }
            }

            Section {
                Button("Use this iPad's own notebook instead") {
                    config.mode = .local
                    config.setupComplete = true
                    env.rebuildDataSource()
                }
                .font(Typography.body(14))
            }
        }
        .navigationTitle("Connect to a server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Back") { page = .choose; result = nil }
            }
        }
    }

    @ViewBuilder
    private func resultRow(_ result: ServerProbe.Result) -> some View {
        switch result {
        case let .ok(count, token):
            VStack(alignment: .leading, spacing: 4) {
                Label("Connected — \(count) recipe\(count == 1 ? "" : "s")",
                      systemImage: "checkmark.circle.fill")
                    .font(Typography.mono(13)).foregroundStyle(Theme.primary)
                switch token {
                case .none:
                    Text("No token — you'll be able to read and cook, but not save edits.")
                        .font(Typography.body(12)).foregroundStyle(Theme.faint)
                case .accepted:
                    Text("Token accepted — saving will work.")
                        .font(Typography.body(12)).foregroundStyle(Theme.faint)
                case .rejected:
                    Text("Token rejected. You can continue and fix it later in Settings.")
                        .font(Typography.body(12)).foregroundStyle(Theme.accent)
                }
            }
        case let .unreachable(why):
            Label(why, systemImage: "xmark.circle.fill")
                .font(Typography.mono(13)).foregroundStyle(Theme.accent)
        case .notSharpEdge:
            Label("That address answered, but it isn't a Sharp Edge server.",
                  systemImage: "questionmark.circle.fill")
                .font(Typography.mono(13)).foregroundStyle(Theme.accent)
        }
    }

    /// Validate first, commit second. Nothing reaches UserDefaults or the Keychain until
    /// the server has actually answered — so a typo cannot leave the app pointed at
    /// nothing with no obvious way back.
    private func probe() async {
        probing = true
        result = nil
        defer { probing = false }

        guard let url = URL(string: urlField.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            result = .unreachable("That doesn't look like a URL.")
            return
        }
        let token = tokenField.trimmingCharacters(in: .whitespacesAndNewlines)
        let outcome = await ServerProbe.check(url: url, token: token)
        result = outcome

        guard case .ok = outcome else { return }
        config.baseURLString = url.absoluteString
        config.token = token
        config.mode = .server
        config.setupComplete = true
        env.rebuildDataSource()
    }
}
