import AVFoundation
import Foundation
import Speech

/// Live dictation via `SFSpeechRecognizer` + `AVAudioEngine`.
///
/// On-device recognition is requested wherever the OS has a local model — true for
/// en-US, fr-FR and de-DE. It is *not* available for ro-RO today, in which case audio
/// goes to Apple's speech service. That difference is surfaced in the UI via
/// `isOnDevice` rather than hidden, because it is the one privacy-relevant thing about
/// this feature. Nothing is sent to the recipe backend or to any model.
@MainActor
final class SpeechRecognizerService: ObservableObject {
    enum Status: Equatable {
        case idle
        case listening
        case denied(String)
        case unavailable(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var transcript = ""
    /// The same speech, but with a line break wherever the speaker paused. Dictation
    /// inserts no punctuation unless you say "period", so pauses are the only
    /// reliable boundary between one ingredient and the next.
    @Published private(set) var pausedTranscript = ""
    @Published private(set) var isOnDevice = false

    private let audioEngine = AVAudioEngine()
    private var recognizer: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    /// Text banked from earlier requests in this session — dictation is restarted
    /// each time the recogniser finalises, so results must accumulate across them.
    private var finalisedText = ""
    private var finalisedLines: [String] = []
    private var wantsToListen = false
    private var activeLanguage: CaptureLanguage = .en

    var isListening: Bool { status == .listening }

    /// Whether the OS can recognise this language at all, and whether it can do so locally.
    func availability(for language: CaptureLanguage) -> (supported: Bool, onDevice: Bool) {
        guard let r = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)) else {
            return (false, false)
        }
        return (r.isAvailable, r.supportsOnDeviceRecognition)
    }

    func start(language: CaptureLanguage) async {
        stop()
        transcript = ""
        pausedTranscript = ""
        finalisedText = ""
        finalisedLines = []
        wantsToListen = true
        activeLanguage = language

        guard await requestPermissions() else { wantsToListen = false; return }

        guard let recognizer = SFSpeechRecognizer(locale: Locale(identifier: language.localeIdentifier)),
              recognizer.isAvailable
        else {
            status = .unavailable("\(language.displayName) dictation isn't available on this device. Type it instead.")
            return
        }
        self.recognizer = recognizer

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        isOnDevice = recognizer.supportsOnDeviceRecognition
        self.request = request

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let input = audioEngine.inputNode
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0)) { buffer, _ in
                request.append(buffer)
            }
            audioEngine.prepare()
            try audioEngine.start()
        } catch {
            status = .unavailable("Couldn't start the microphone. \(error.localizedDescription)")
            return
        }

        status = .listening
        listen(with: recognizer, request: request)
    }

    /// The recogniser reports `isFinal` after a natural pause — which, when you are
    /// reading out an ingredient list, is after every item. Ending the session there
    /// truncated dictation to the first line or two. Instead the finished text is
    /// banked and a fresh request started, so speaking continues until Stop is
    /// tapped. This also covers the ~1 minute ceiling on server-side recognition,
    /// which ends a request the same way.
    private func listen(with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest) {
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    let live = result.bestTranscription.formattedString
                    let liveLines = Self.breakOnPauses(result.bestTranscription)
                    self.transcript = Self.join(self.finalisedText, live)
                    self.pausedTranscript = Self.joinLines(self.finalisedLines, liveLines)

                    if result.isFinal {
                        self.finalisedText = self.transcript
                        self.finalisedLines = self.pausedTranscript
                            .split(separator: "\n").map(String.init)
                        self.restartIfWanted()
                        return
                    }
                }
                if error != nil {
                    // A timeout or a silence-triggered end is not a failure while the
                    // user still has the mic open; only a real stop should end it.
                    self.restartIfWanted()
                }
            }
        }
    }

    private func restartIfWanted() {
        task?.cancel()
        task = nil
        request?.endAudio()
        request = nil
        guard wantsToListen, let recognizer, audioEngine.isRunning else {
            if !wantsToListen { stop() }
            return
        }
        let next = SFSpeechAudioBufferRecognitionRequest()
        next.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition { next.requiresOnDeviceRecognition = true }
        request = next
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024,
                                         format: audioEngine.inputNode.outputFormat(forBus: 0)) { buffer, _ in
            next.append(buffer)
        }
        listen(with: recognizer, request: next)
    }

    private static func join(_ banked: String, _ live: String) -> String {
        banked.isEmpty ? live : (live.isEmpty ? banked : banked + " " + live)
    }

    private static func joinLines(_ banked: [String], _ live: String) -> String {
        let liveLines = live.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return (banked + liveLines).joined(separator: "\n")
    }

    func stop() {
        wantsToListen = false
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if status == .listening { status = .idle }
    }

    /// Test seam — lets the simulator drive the flow without a microphone.
    func setTranscript(_ text: String) {
        transcript = text
        pausedTranscript = text
    }

    /// A gap between spoken segments means "next item". 0.45s is comfortably longer
    /// than the gap between words in a phrase and shorter than the beat someone
    /// leaves between list items.
    static let pauseThreshold: TimeInterval = 0.45

    static func breakOnPauses(_ transcription: SFTranscription) -> String {
        var lines: [String] = []
        var current = ""
        var previousEnd: TimeInterval?

        for segment in transcription.segments {
            if let end = previousEnd, segment.timestamp - end >= pauseThreshold, !current.isEmpty {
                lines.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            }
            current += (current.isEmpty ? "" : " ") + segment.substring
            previousEnd = segment.timestamp + segment.duration
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            lines.append(current.trimmingCharacters(in: .whitespaces))
        }
        // Some recognisers report all-zero timings; then this yields one line and the
        // server-side quantity splitter takes over.
        return lines.joined(separator: "\n")
    }

    private func requestPermissions() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else {
            status = .denied("Speech recognition is off for this app. Turn it on in Settings → Privacy.")
            return false
        }
        let mic = await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { continuation.resume(returning: $0) }
        }
        guard mic else {
            status = .denied("The microphone is off for this app. Turn it on in Settings → Privacy.")
            return false
        }
        return true
    }
}
