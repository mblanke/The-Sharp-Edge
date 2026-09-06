import AVFoundation
import SwiftUI

/// Full-screen, one-step-per-screen cook mode. Keeps the screen awake, shows scaled
/// amounts for the active step, runs timers that outlive the step (see `TimerCenter`),
/// resumes where the cook left off, and takes "next" / "back" / "start timer" by voice.
struct CookModeView: View {
    let recipe: RecipeFull
    let target: Int
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var timers: TimerCenter

    @State private var index: Int = 0
    @State private var showIngredients = false
    @State private var resumedFrom: Int? = nil

    @StateObject private var speech = SpeechRecognizerService()
    @State private var voiceOn = false
    @State private var voiceStream = CookVoiceStream()
    @State private var synth = AVSpeechSynthesizer()

    private var steps: [Step] { recipe.currentVersion.steps }
    private var scaledRows: [ScaledRow] {
        ScalingEngine.scale(recipe.currentVersion.ingredients, baseYield: recipe.baseYield, targetYield: target)
    }
    private var posKey: String { "sharpedge.cookpos.\(recipe.slug)" }
    private var currentTimerId: String { CookTimer.id(slug: recipe.slug, step: index) }

    var body: some View {
        ZStack {
            Theme.paper.ignoresSafeArea()
            VStack(spacing: 0) {
                topBar
                TimerTrayView(exclude: currentTimerId) { timer in
                    withAnimation { index = min(steps.count - 1, max(0, timer.step)) }
                }
                if let from = resumedFrom { resumeBanner(from) }
                if voiceOn { voiceStatus }
                TabView(selection: $index) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        stepPage(idx: idx, step: step).tag(idx)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .overlay(alignment: .bottom) { pageDots }
            }
            keyboardShortcuts
        }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true
            let saved = UserDefaults.standard.integer(forKey: posKey)
            if saved > 0 && saved < steps.count {
                index = saved
                resumedFrom = saved
            }
        }
        .onChange(of: index) { _, newValue in
            UserDefaults.standard.set(newValue, forKey: posKey)
            resumedFrom = nil
        }
        .onChange(of: speech.transcript) { _, transcript in
            guard voiceOn, let command = voiceStream.commands(in: transcript) else { return }
            perform(command)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            if voiceOn { speech.stop() }
        }
        .sheet(isPresented: $showIngredients) { ingredientSheet }
    }

    // MARK: chrome

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Exit cook mode")
            Spacer()
            Text("\(index + 1) / \(steps.count)")
                .font(Typography.mono(15, weight: .semibold)).foregroundStyle(Theme.faint)
                .accessibilityLabel("Step \(index + 1) of \(steps.count)")
            Spacer()
            Button { toggleVoice() } label: {
                Image(systemName: voiceOn ? "mic.fill" : "mic")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(voiceOn ? Theme.offWhite : Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(voiceOn ? Theme.accent : Color.clear, in: Circle())
            }
            .accessibilityLabel(voiceOn ? "Stop voice control" : "Start voice control")
            Button { showIngredients = true } label: {
                Image(systemName: "list.bullet").font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.ink).frame(width: 44, height: 44)
            }
            .accessibilityLabel("Show all ingredients")
        }
        .padding(.horizontal, Theme.Space.l)
    }

    private func resumeBanner(_ from: Int) -> some View {
        HStack {
            Text("Picked up at step \(from + 1)")
                .font(Typography.mono(12)).foregroundStyle(Theme.faint)
            Spacer()
            Button("Start over") {
                withAnimation { index = 0 }
            }
            .font(Typography.mono(12, weight: .semibold))
            .foregroundStyle(Theme.inkAccent)
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.s)
    }

    private var voiceStatus: some View {
        Text(voiceStatusText)
            .font(Typography.mono(11))
            .foregroundStyle(Theme.faint)
            .multilineTextAlignment(.center)
            .padding(.horizontal, Theme.Space.l)
            .padding(.bottom, Theme.Space.xs)
    }

    private var voiceStatusText: String {
        switch speech.status {
        case .listening:
            return "listening — say \"next\", \"back\", \"repeat\", \"start timer\""
        case let .denied(message), let .unavailable(message):
            return message
        case .idle:
            return "starting the microphone…"
        }
    }

    /// Hardware keyboards on iPad: arrows and space move, T toggles the timer, Escape exits.
    private var keyboardShortcuts: some View {
        Group {
            Button("Next") { advance(1) }.keyboardShortcut(.rightArrow, modifiers: [])
            Button("Next") { advance(1) }.keyboardShortcut(.space, modifiers: [])
            Button("Back") { advance(-1) }.keyboardShortcut(.leftArrow, modifiers: [])
            Button("Timer") { toggleTimer() }.keyboardShortcut("t", modifiers: [])
            Button("Ingredients") { showIngredients = true }.keyboardShortcut("i", modifiers: [])
            Button("Exit") { dismiss() }.keyboardShortcut(.escape, modifiers: [])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: pages

    /// Centred when the step fits, scrollable when it doesn't (long steps, landscape,
    /// large type) — a fixed centre used to clip the timer off the bottom.
    private func stepPage(idx: Int, step: Step) -> some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Space.xl) {
                    Text("Step \(idx + 1)")
                        .font(Typography.mono(16, weight: .semibold)).foregroundStyle(Theme.accent)
                    Text(StepText.attributed(step.text))
                        .font(Typography.display(30, weight: .regular))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    if let t = step.timerSeconds {
                        CookTimerView(slug: recipe.slug, title: recipe.title, step: idx, seconds: t)
                    }
                    navButtons(idx: idx)
                }
                .padding(Theme.Space.xxl)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
                .frame(minHeight: geo.size.height)
            }
        }
    }

    private func navButtons(idx: Int) -> some View {
        HStack(spacing: Theme.Space.l) {
            Button {
                withAnimation { index = max(0, idx - 1) }
            } label: { Label("Back", systemImage: "chevron.left") }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(idx == 0)
                .opacity(idx == 0 ? 0.4 : 1)

            Button {
                if idx == steps.count - 1 {
                    UserDefaults.standard.removeObject(forKey: posKey)
                    dismiss()
                } else {
                    withAnimation { index = idx + 1 }
                }
            } label: { Label(idx == steps.count - 1 ? "Done" : "Next",
                             systemImage: idx == steps.count - 1 ? "checkmark" : "chevron.right") }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<steps.count, id: \.self) { i in
                Circle().fill(i == index ? Theme.primary : Theme.line)
                    .frame(width: 7, height: 7)
            }
        }
        .padding(.bottom, 10)
        .accessibilityHidden(true)
    }

    private var ingredientSheet: some View {
        NavigationStack {
            List {
                ForEach(Grouping.sections(scaledRows)) { section in
                    Section(section.name ?? "Ingredients") {
                        ForEach(section.rows) { row in
                            HStack {
                                Text(row.display).font(Typography.mono(15, weight: .semibold))
                                    .foregroundStyle(Theme.inkAccent).frame(minWidth: 70, alignment: .leading)
                                Text(row.name).font(Typography.body(15))
                            }
                        }
                    }
                }
            }
            .navigationTitle("\(target) \(recipe.yieldWord)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showIngredients = false } } }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: actions

    private func advance(_ delta: Int) {
        withAnimation { index = min(steps.count - 1, max(0, index + delta)) }
    }

    private func toggleTimer() {
        guard let seconds = steps[index].timerSeconds else { return }
        CookTimerView(slug: recipe.slug, title: recipe.title, step: index, seconds: seconds)
            .toggle(in: timers)
    }

    private func perform(_ command: CookVoiceCommand) {
        switch command {
        case .next: advance(1)
        case .back: advance(-1)
        case .repeatStep: speakStep()
        case .timerStart:
            guard let seconds = steps[index].timerSeconds else { return }
            let t = timers.ensure(slug: recipe.slug, title: recipe.title, step: index, total: TimeInterval(seconds))
            if t.isDone(at: timers.now) { timers.reset(id: t.id) }
            timers.start(id: t.id)
        case .timerPause: timers.pause(id: currentTimerId)
        case .timerReset: timers.reset(id: currentTimerId)
        }
    }

    private func toggleVoice() {
        if voiceOn {
            voiceOn = false
            speech.stop()
            return
        }
        voiceOn = true
        voiceStream = CookVoiceStream()
        Task {
            await speech.start(language: .en)
            // dictation opens the session record-only; we also need to talk back
            try? AVAudioSession.sharedInstance()
                .setCategory(.playAndRecord, mode: .default, options: [.duckOthers, .defaultToSpeaker])
        }
    }

    private func speakStep() {
        let text = steps[index].text.replacingOccurrences(of: "**", with: "")
        synth.stopSpeaking(at: .immediate)
        synth.speak(AVSpeechUtterance(string: text))
    }
}

private extension CookTimerView {
    /// The view's own toggle needs its environment; from a keyboard shortcut we have the
    /// centre in hand instead.
    func toggle(in center: TimerCenter) {
        let id = CookTimer.id(slug: slug, step: step)
        if center.timer(slug: slug, step: step)?.isRunning == true {
            center.pause(id: id)
        } else {
            let t = center.ensure(slug: slug, title: title, step: step, total: TimeInterval(seconds))
            if t.isDone(at: center.now) { center.reset(id: id) }
            center.start(id: id)
        }
    }
}
