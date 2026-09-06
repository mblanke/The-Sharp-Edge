import SwiftUI

/// Every timer that is running, paused mid-way, or finished — on any screen. Inside
/// cook mode the current step's timer is excluded because it renders large inline.
struct TimerTrayView: View {
    @EnvironmentObject var center: TimerCenter
    var exclude: String? = nil
    var onOpen: ((CookTimer) -> Void)? = nil

    private var rows: [CookTimer] {
        center.active().filter { $0.id != exclude }
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: Theme.Space.xs) {
                ForEach(rows) { timer in
                    row(timer)
                }
            }
            .padding(.horizontal, Theme.Space.l)
            .padding(.vertical, Theme.Space.s)
            .background(Theme.paper)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Running timers")
        }
    }

    private func row(_ timer: CookTimer) -> some View {
        let done = timer.isDone(at: center.now)
        return HStack(spacing: Theme.Space.m) {
            Button {
                onOpen?(timer)
            } label: {
                Text(timer.label)
                    .font(Typography.mono(12, weight: .semibold))
                    .foregroundStyle(done ? Theme.accent : Theme.faint)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(onOpen == nil)

            Text(done ? "done" : CookTimerView.timeString(timer.remaining(at: center.now)))
                .font(Typography.mono(17, weight: .semibold))
                .foregroundStyle(done ? Theme.accent : Theme.inkAccent)
                .monospacedDigit()

            if !done {
                Button {
                    timer.isRunning ? center.pause(id: timer.id) : center.start(id: timer.id)
                } label: {
                    Image(systemName: timer.isRunning ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Theme.inkAccent)
                        .frame(width: 36, height: 36)
                        .background(Theme.card, in: Circle())
                        .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                }
                .accessibilityLabel(timer.isRunning ? "Pause \(timer.label)" : "Resume \(timer.label)")
            }

            Button {
                center.remove(id: timer.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Theme.faint)
                    .frame(width: 36, height: 36)
                    .background(Theme.card, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1))
            }
            .accessibilityLabel("Dismiss \(timer.label)")
        }
        .frame(minHeight: Theme.minTouch)
        .padding(.horizontal, Theme.Space.m)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous)
                .stroke(done ? Theme.accent : Theme.line, lineWidth: 1)
        )
    }
}
