import AVFAudio
import Foundation

/// Speaks alert phrases through the current output route using the app's audio session.
/// It requests `.spokenPrompt` from the coordinator and releases it when speech finishes.
@MainActor
final class SpeechAlertSpeaker: NSObject, AlertSpeaking {
    private let synthesizer = AVSpeechSynthesizer()
    private let coordinator: AudioSessionCoordinator
    private(set) var lastError: String?
    private(set) var lastSpoken: String?

    init(coordinator: AudioSessionCoordinator) {
        self.coordinator = coordinator
        super.init()
        synthesizer.delegate = self
        synthesizer.usesApplicationAudioSession = true
    }

    func speak(_ phrase: AlertPhrase, priority: SpeechPriority) {
        do {
            try coordinator.acquire(.spokenPrompt)
        } catch {
            lastError = error.localizedDescription
            return
        }
        if priority == .high, synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: phrase.text)
        utterance.prefersAssistiveTechnologySettings = true
        utterance.voice = AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
        lastSpoken = phrase.text
        synthesizer.speak(utterance)
    }

    fileprivate func utteranceEnded() {
        // Give queued utterances a moment to start before releasing the session.
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(200))
            guard let self, !self.synthesizer.isSpeaking else { return }
            self.coordinator.release(.spokenPrompt)
        }
    }
}

extension SpeechAlertSpeaker: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.utteranceEnded() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in self?.utteranceEnded() }
    }
}
