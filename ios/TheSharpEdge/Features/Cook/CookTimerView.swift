import SwiftUI

/// Inline countdown for a step. The state lives in `TimerCenter`, so swiping to the
/// next step, closing cook mode, or locking the iPad does not stop the clock.
struct CookTimerView: View {
    @EnvironmentObject var center: TimerCenter
    let slug: String
    let title: String
    let step: Int
    let seconds: Int

    private var timer: CookTimer? { center.timer(slug: slug, step: step) }
    private var remaining: TimeInterval { timer?.remaining(at: center.now) ?? TimeInterval(seconds) }
    private var running: Bool { timer?.isRunning ?? false }
    private var done: Bool { timer?.isDone(at: center.now) ?? false }

    var body: some View {
        HStack(spacing: Theme.Space.m) {
            Image(systemName: "timer").foregroundStyle(Theme.accent)
            Text(Self.timeString(remaining))
                .font(Typography.mono(26, weight: .semibold))
                .foregroundStyle(done ? Theme.accent : Theme.ink)
                .monospacedDigit()
                .accessibilityLabel(done ? "Timer done" : "\(Self.timeString(remaining)) remaining")
            Button {
                toggle()
            } label: {
                Image(systemName: running ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.offWhite)
                    .frame(width: 40, height: 40)
                    .background(Theme.primaryDeep, in: Circle())
            }
            .accessibilityLabel(running ? "Pause timer" : (done ? "Start timer again" : "Start timer"))
            Button {
                reset()
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.inkAccent)
                    .frame(width: 40, height: 40)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .accessibilityLabel("Reset timer")
        }
        .padding(Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
            .stroke(done ? Theme.accent : Theme.line, lineWidth: 1))
        .sensoryFeedback(.success, trigger: done)
    }

    func toggle() {
        let id = CookTimer.id(slug: slug, step: step)
        if running {
            center.pause(id: id)
        } else {
            let t = center.ensure(slug: slug, title: title, step: step, total: TimeInterval(seconds))
            if t.isDone(at: center.now) { center.reset(id: id) }
            center.start(id: id)
        }
    }

    func reset() {
        center.reset(id: CookTimer.id(slug: slug, step: step))
    }

    static func timeString(_ seconds: TimeInterval) -> String {
        let s = Int(seconds.rounded(.up))
        if s >= 3600 { return String(format: "%d:%02d:%02d", s / 3600, (s % 3600) / 60, s % 60) }
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}
