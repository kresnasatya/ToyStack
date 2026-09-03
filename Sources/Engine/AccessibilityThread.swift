import AVFoundation

final class AccessibilityThread: NSObject, @unchecked Sendable, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    private var politeQueue: [String] = []
    private var isSpeaking = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        print("SPEAK:", text)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synthesizer.speak(utterance)
    }

    func speakPolite(_ text: String) {
        if isSpeaking {
            politeQueue.append(text)
        } else {
            speak(text)
        }
    }

    func stopSpeaking() {
        synthesizer.stopSpeaking(at: .immediate)
        politeQueue.removeAll()
    }

    func speakUrgent(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        politeQueue.removeAll()
        speak(text)
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
        if let next = politeQueue.first {
            politeQueue.removeFirst()
            speak(next)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        isSpeaking = true
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
}
