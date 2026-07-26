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

        guard await requestPermissions() else { return }

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
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.pausedTranscript = Self.breakOnPauses(result.bestTranscription)
                }
                if error != nil || result?.isFinal == true {
                    self.stop()
                }
            }
        }
    }

    func stop() {
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
