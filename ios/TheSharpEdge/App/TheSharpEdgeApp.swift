import SwiftUI

@main
struct TheSharpEdgeApp: App {
    @StateObject private var env = AppEnvironment()
    /// Cook timers outlive the screen that started them (a braise does not care which
    /// step you are looking at), so they are owned here and read everywhere.
    @StateObject private var timers = TimerCenter()

    init() {
        FontRegistrar.registerIfPresent()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(env)
                .environmentObject(env.offline)
                .environmentObject(env.config)
                .environmentObject(timers)
                .tint(Theme.primary)
        }
    }
}
