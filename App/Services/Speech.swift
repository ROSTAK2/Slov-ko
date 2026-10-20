import AVFoundation

/// Озвучка словацкого через встроенный синтезатор iOS (голос sk-SK).
final class Speech {
    static let shared = Speech()

    private let synthesizer = AVSpeechSynthesizer()
    var rate: Float = 0.45

    private lazy var voice: AVSpeechSynthesisVoice? = {
        let slovak = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix("sk") }
        return slovak.max(by: { $0.quality.rawValue < $1.quality.rawValue })
            ?? AVSpeechSynthesisVoice(language: "sk-SK")
    }()

    var hasSlovakVoice: Bool { voice != nil }

    /// true, если установлен улучшенный (не «компактный») голос.
    var hasEnhancedVoice: Bool {
        guard let voice else { return false }
        return voice.quality != .default
    }

    func speak(_ text: String, slow: Bool = false) {
        let clean = text.replacingOccurrences(of: "___", with: "…")
        guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = voice
        utterance.rate = slow ? rate * 0.6 : rate
        synthesizer.speak(utterance)
    }
}
