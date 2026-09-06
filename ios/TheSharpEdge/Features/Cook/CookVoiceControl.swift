import Foundation

/// Hands-free cook mode: the same short vocabulary the web cook page understands.
/// Recognition is on-device where the OS allows (see `SpeechRecognizerService`);
/// nothing is sent anywhere.
enum CookVoiceCommand: Equatable {
    case next, back, repeatStep, timerStart, timerPause, timerReset

    /// The trailing words of a live transcript, matched loosely: "ok next" and
    /// "next step please" both advance. Returns nil when the tail is not a command.
    static func parse(_ tail: String) -> CookVoiceCommand? {
        let words = tail.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .suffix(4)
        let phrase = words.joined(separator: " ")
        if phrase.hasSuffix("start timer") || phrase.hasSuffix("start the timer") || phrase.hasSuffix("resume timer") {
            return .timerStart
        }
        if phrase.hasSuffix("pause timer") || phrase.hasSuffix("stop timer") || phrase.hasSuffix("stop the timer") {
            return .timerPause
        }
        if phrase.hasSuffix("reset timer") { return .timerReset }
        guard let last = words.last else { return nil }
        switch last {
        case "next", "forward", "continue", "done": return .next
        case "back", "previous": return .back
        case "repeat", "again": return .repeatStep
        default:
            if phrase.hasSuffix("next step") { return .next }
            if phrase.hasSuffix("go back") || phrase.hasSuffix("last step") { return .back }
            return nil
        }
    }
}

/// Turns a growing dictation transcript into discrete commands: each transcript
/// update is compared against the last handled length, and only the new tail is
/// parsed, so "next" fires once per utterance rather than once per partial result.
struct CookVoiceStream {
    private(set) var handled = 0

    mutating func commands(in transcript: String) -> CookVoiceCommand? {
        if transcript.count < handled { handled = 0 } // recogniser restarted: fresh text
        guard transcript.count > handled else { return nil }
        let tail = String(transcript.dropFirst(handled))
        guard let command = CookVoiceCommand.parse(tail) else { return nil }
        handled = transcript.count
        return command
    }
}
