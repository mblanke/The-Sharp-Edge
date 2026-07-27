import SwiftUI

/// "You are looking at a saved copy." Deliberately quiet — a dropped network while
/// cooking is not an error state, it is a slightly older recipe, and the app should
/// keep working rather than shout.
struct OfflineBanner: View {
    @EnvironmentObject var offline: OfflineState

    var body: some View {
        if offline.servingCache {
            HStack(spacing: 6) {
                Image(systemName: "wifi.slash")
                Text("Saved copy — can't reach the server\(synced)")
            }
            .font(Typography.mono(11))
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, 6)
            .background(Theme.card)
        }
    }

    private var synced: String {
        guard let at = offline.lastSynced else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return ", last updated " + f.localizedString(for: at, relativeTo: Date())
    }
}
