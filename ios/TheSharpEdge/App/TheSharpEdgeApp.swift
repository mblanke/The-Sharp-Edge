import SwiftUI

@main
struct TheSharpEdgeApp: App {
    @StateObject private var env = AppEnvironment()

    init() {
        FontRegistrar.registerIfPresent()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.offline)
                .environmentObject(env.config)
                .tint(Theme.primary)
        }
    }
}
