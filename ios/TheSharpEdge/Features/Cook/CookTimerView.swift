import SwiftUI

/// Inline countdown timer for a step (seeded from timer_seconds).
struct CookTimerView: View {
    let seconds: Int
    @State private var remaining: Int
    @State private var running = false
    @State private var ticker: Timer?

    init(seconds: Int) {
        self.seconds = seconds
        _remaining = State(initialValue: seconds)
    }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "timer").foregroundStyle(Theme.accent)
            Text(timeString(remaining))
                .font(Typography.mono(26, weight: .semibold))
                .foregroundStyle(remaining == 0 ? Theme.accent : Theme.ink)
                .monospacedDigit()
            Button {
                running ? stop() : start()
            } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.offWhite)
                    .frame(width: 40, height: 40)
                    .background(Theme.primaryDeep, in: Circle())
            }
            Button {
                stop(); remaining = seconds
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.primaryDeep)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
        }
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous).stroke(Theme.line, lineWidth: 1))
        .onDisappear { stop() }
    }

    private func start() {
        guard remaining > 0 else { return }
        running = true
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            if remaining > 0 {
                remaining -= 1
            } else {
                stop()
            }
        }
    }

    private func stop() {
        running = false
        ticker?.invalidate()
        ticker = nil
    }

    private func timeString(_ s: Int) -> String {
        String(format: "%d:%02d", s / 60, s % 60)
    }
}
