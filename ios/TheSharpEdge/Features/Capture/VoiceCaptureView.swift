import SwiftUI

/// Dictate a recipe standing at the counter, in English, French, German or Romanian.
///
/// Four prompts — title, category, ingredients, method. Each one lands in an editable
/// text field, and the whole thing then opens the normal add-recipe form, because
/// dictation is never 100% right and the review step *is* the answer to that. There is
/// no separate "voice recipe" path to keep in sync.
///
/// Structured fields (amount, unit, category) normalise to the app's canonical English
/// set; the words you say — the title, the ingredient names, the method — are kept
/// exactly as spoken. Nothing is translated and no model is involved.
struct VoiceCaptureView: View {
    var onCaptured: (RecipeCreate) -> Void

    @EnvironmentObject var env: AppEnvironment
    @EnvironmentObject var config: AppConfig
    @Environment(\.dismiss) private var dismiss
    @StateObject private var speech = SpeechRecognizerService()

    @State private var language: CaptureLanguage = .en
    @State private var stage: Stage = .title
    @State private var titleText = ""
    @State private var categoryText = ""
    @State private var ingredientsText = ""
    @State private var methodText = ""
    @State private var building = false

    private enum Stage: Int, CaseIterable {
        case title, category, ingredients, method

        var prompt: String {
            switch self {
            case .title: return "What's the recipe called?"
            case .category: return "What kind of recipe is it?"
            case .ingredients: return "What goes in it?"
            case .method: return "How do you make it?"
            }
        }

        var hint: String {
            switch self {
            case .title: return "Just the name."
            case .category: return "Say a category — soups, salads, desserts…"
            case .ingredients: return "One per line. Say “to taste” where there's no measurement."
            case .method: return "One step per line."
            }
        }

        var multiline: Bool { self == .ingredients || self == .method }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                languageBar
                progressBar

                Text(stage.prompt)
                    .font(Typography.display(26))
                    .foregroundStyle(Theme.ink)
                Text(stage.hint)
                    .font(Typography.body(14))
                    .foregroundStyle(Theme.faint)

                editor

                if let notice { noticeRow(notice) }

                Spacer(minLength: 0)
                micButton
                #if DEBUG
                simulatedDictation
                #endif
                navRow
            }
            .padding(Theme.Space.xl)
            .background(Theme.paper)
            .navigationTitle("Dictate a recipe")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { speech.stop(); dismiss() }
                }
            }
            .onAppear {
                language = config.captureLanguage
                #if DEBUG
                applyScreenshotHook()
                #endif
            }
            .onDisappear { speech.stop() }
            .onChange(of: speech.transcript) { _, text in
                guard !text.isEmpty else { return }
                // Prefer the pause-segmented version for the list stages: dictation
                // produces no punctuation, so pauses are the real item boundary.
                write(stage.multiline && !speech.pausedTranscript.isEmpty
                      ? speech.pausedTranscript : text)
            }
        }
    }

    // MARK: - Pieces

    private var languageBar: some View {
        HStack(spacing: Theme.Space.s) {
            ForEach(CaptureLanguage.allCases) { lang in
                let selected = lang == language
                Button {
                    speech.stop()
                    language = lang
                    config.captureLanguage = lang
                } label: {
                    Text("\(lang.flag)  \(lang.displayName)")
                        .font(Typography.mono(12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 36)
                        .background(selected ? Theme.primaryDeep : Color.clear)
                        .foregroundStyle(selected ? Theme.offWhite : Theme.primaryDeep)
                        .clipShape(Capsule())
                        .overlay(Capsule().stroke(Theme.line, lineWidth: selected ? 0 : 1))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var progressBar: some View {
        HStack(spacing: 6) {
            ForEach(Stage.allCases, id: \.rawValue) { s in
                Capsule()
                    .fill(s.rawValue <= stage.rawValue ? Theme.primary : Theme.line)
                    .frame(height: 4)
            }
        }
    }

    private var editor: some View {
        TextEditor(text: binding(for: stage))
            .font(stage.multiline ? Typography.mono(15) : Typography.body(19))
            .scrollContentBackground(.hidden)
            .padding(Theme.Space.m)
            .frame(minHeight: stage.multiline ? 200 : 90)
            .background(Theme.card)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.md).stroke(Theme.line, lineWidth: 1))
    }

    private var micButton: some View {
        Button {
            if speech.isListening {
                speech.stop()
            } else {
                Task { await speech.start(language: language) }
            }
        } label: {
            Label(speech.isListening ? "Stop" : "Hold the thought — tap to dictate",
                  systemImage: speech.isListening ? "stop.circle.fill" : "mic.fill")
                .font(Typography.body(16, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 52)
                .background(speech.isListening ? Theme.accent : Theme.primaryDeep)
                .foregroundStyle(Theme.offWhite)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
        }
        .buttonStyle(.plain)
    }

    #if DEBUG
    /// Screenshot hook: open in a given language with the canned dictation already in.
    private func applyScreenshotHook() {
        let env = ProcessInfo.processInfo.environment
        guard let code = env["UITEST_LANG"], let lang = CaptureLanguage(rawValue: code) else { return }
        language = lang
        titleText = SampleData.dictation(lang, 0)
        categoryText = SampleData.dictation(lang, 1)
        ingredientsText = Utterances.split(SampleData.dictation(lang, 2)).joined(separator: "\n")
        methodText = Utterances.split(SampleData.dictation(lang, 3)).joined(separator: "\n")
        if let raw = env["UITEST_STAGE"], let n = Int(raw), let s = Stage(rawValue: n) { stage = s }
    }

    /// The simulator has no usable microphone path and reports no on-device model, so
    /// the flow would be unreviewable there. This fills the current field with a real
    /// dictated line in the selected language.
    private var simulatedDictation: some View {
        Button {
            write(SampleData.dictation(language, stage.rawValue))
        } label: {
            Label("Simulate dictation", systemImage: "waveform")
                .font(Typography.mono(12))
                .frame(maxWidth: .infinity, minHeight: 38)
                .foregroundStyle(Theme.faint)
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.sm)
                    .stroke(Theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
        }
        .buttonStyle(.plain)
    }
    #endif

    private var navRow: some View {
        HStack {
            if stage != .title {
                Button("Back") { speech.stop(); step(-1) }
                    .font(Typography.body(16))
                    .frame(minHeight: Theme.minTouch)
            }
            Spacer()
            if stage == .method {
                Button {
                    speech.stop()
                    Task { await build() }
                } label: {
                    if building { ProgressView() } else { Text("Review recipe") }
                }
                .font(Typography.body(16, weight: .semibold))
                .disabled(building || titleText.trimmingCharacters(in: .whitespaces).isEmpty)
                .frame(minHeight: Theme.minTouch)
            } else {
                Button("Next") { speech.stop(); step(1) }
                    .font(Typography.body(16, weight: .semibold))
                    .frame(minHeight: Theme.minTouch)
            }
        }
    }

    /// Shown before you speak, not after — where the audio goes is something to know
    /// in advance. ro-RO has no on-device model today, so it is transcribed by Apple's
    /// speech service; en/fr/de stay on the device.
    private var notice: String? {
        switch speech.status {
        case let .denied(message), let .unavailable(message):
            return message
        default:
            #if targetEnvironment(simulator)
            // The simulator reports no on-device model for every language, so don't
            // claim anything here that would be wrong on a real iPad.
            return "Simulator — on-device models aren't available here. On device: English, Français and Deutsch stay local; Română uses Apple's speech service."
            #else
            let availability = speech.availability(for: language)
            if !availability.supported {
                return "\(language.displayName) dictation isn't available on this device. Type it instead."
            }
            return availability.onDevice
                ? "\(language.displayName) is transcribed on this device."
                : "\(language.displayName) has no on-device model — audio is transcribed by Apple's speech service."
            #endif
        }
    }

    private var onDeviceHere: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        return speech.availability(for: language).onDevice
        #endif
    }

    private var noticeIcon: String {
        onDeviceHere ? "lock.iphone" : "icloud.and.arrow.up"
    }

    private func noticeRow(_ text: String) -> some View {
        Label(text, systemImage: noticeIcon)
            .font(Typography.body(13))
            .foregroundStyle(onDeviceHere ? Theme.faint : Theme.accent)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Behaviour

    private func binding(for stage: Stage) -> Binding<String> {
        switch stage {
        case .title: return $titleText
        case .category: return $categoryText
        case .ingredients: return $ingredientsText
        case .method: return $methodText
        }
    }

    /// Live transcript → the current field. Multi-line stages split on the pauses that
    /// dictation renders as sentence punctuation, one utterance per line.
    private func write(_ text: String) {
        if stage.multiline {
            // Keep existing line breaks (from pause detection) and split further on any
            // punctuation the recogniser did manage to insert.
            let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
                .flatMap { Utterances.split(String($0)) }
            binding(for: stage).wrappedValue = lines.joined(separator: "\n")
        } else {
            binding(for: stage).wrappedValue = text
        }
    }

    private func step(_ delta: Int) {
        let next = stage.rawValue + delta
        guard let s = Stage(rawValue: next) else { return }
        stage = s
    }

    private func build() async {
        building = true
        defer { building = false }

        let ingredientLines = ingredientsText.split(separator: "\n").map(String.init)
        let ingredients = (try? await env.dataSource.parseIngredients(ingredientLines, lang: language)) ?? []
        // Unrecognised category → the first one; the review screen has a picker.
        let matched = try? await env.dataSource.category(for: categoryText, lang: language)
        let category = matched.flatMap { $0 } ?? Category.order[0]
        let slug = (try? await env.dataSource.slug(for: titleText))?.slug ?? ""

        onCaptured(RecipeCreate(
            slug: slug,
            title: titleText.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            baseYield: 4,
            // A half-dictated recipe stays out of the index until it's been reviewed
            // on a bigger screen. There is no DELETE endpoint, so drafts are the only
            // way back from an accidental save.
            status: "draft",
            ingredients: ingredients,
            steps: Utterances.split(methodText).map { Step(text: $0) },
            notes: []))
    }
}

/// Splitting a continuous take into lines. Kept out of the view so it is testable.
enum Utterances {
    static func split(_ text: String) -> [String] {
        text
            .replacingOccurrences(of: "\n", with: ". ")
            .split(whereSeparator: { $0 == "." || $0 == ";" || $0 == "\n" })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
