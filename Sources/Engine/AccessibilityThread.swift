import AVFoundation
import Foundation

final class AccessibilityThread: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "browser.accessibility")
    private let synthesizer = AVSpeechSynthesizer()
    private let utteranceDone = DispatchSemaphore(value: 0)

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        queue.async {
            print("SPEAK:", text)
            let utterance = AVSpeechUtterance(string: text)
            self.synthesizer.speak(utterance)
            self.utteranceDone.wait()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        utteranceDone.signal()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        utteranceDone.signal()
    }
}
