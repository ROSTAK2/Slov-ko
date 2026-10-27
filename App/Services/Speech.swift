import AVFoundation

/// Озвучка словацкого через встроенный синтезатор iOS.
///
/// Если словацкого голоса на устройстве нет, iOS молча читает текст системным
/// (например, русским) голосом — и «my» звучит как английское «май». Поэтому:
/// 1) ищем словацкий голос; 2) если его нет — чешский (произношение почти такое же);
/// 3) показываем пользователю предупреждение, как установить словацкий голос.
final class Speech {
    static let shared = Speech()

    enum VoiceStatus {
        case slovak(enhanced: Bool)
        case czechFallback
        case missing
    }

    private let synthesizer = AVSpeechSynthesizer()
    var rate: Float = 0.45
    private var voice: AVSpeechSynthesisVoice?
    private(set) var status: VoiceStatus = .missing

    private init() {
        refreshVoice()
    }

    /// Вызывается при запуске и возвращении в приложение — вдруг голос только что скачали.
    func refreshVoice() {
        let all = AVSpeechSynthesisVoice.speechVoices()
        let best: (String) -> AVSpeechSynthesisVoice? = { prefix in
            all.filter { $0.language.hasPrefix(prefix) }
                .max(by: { $0.quality.rawValue < $1.quality.rawValue })
        }
        if let slovak = best("sk") {
            voice = slovak
            status = .slovak(enhanced: slovak.quality != .default)
        } else if let czech = best("cs") {
            voice = czech
            status = .czechFallback
        } else {
            voice = AVSpeechSynthesisVoice(language: "sk-SK")
            status = voice == nil ? .missing : .slovak(enhanced: false)
        }
    }

    var hasSlovakVoice: Bool {
        if case .slovak = status { return true }
        return false
    }

    var hasEnhancedVoice: Bool {
        if case .slovak(let enhanced) = status { return enhanced }
        return false
    }

    func speak(_ text: String, slow: Bool = false) {
        let clean = Self.pronounceable(text)
        guard !clean.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        let utterance = AVSpeechUtterance(string: clean)
        utterance.voice = voice
        utterance.rate = slow ? rate * 0.6 : rate
        synthesizer.speak(utterance)
    }

    // MARK: - Произношение

    /// Сокращения и заимствования, которые синтезатор читает неправильно.
    private static let overrides: [String: String] = [
        "PN": "pé en",
        "PN-ke": "pé en ke",
        "IT": "í tí",
        "MHD": "em há dé",
        "IBAN": "íban",
        "A1": "á jedna", "A2": "á dva", "B1": "bé jedna", "B2": "bé dva", "C1": "cé jedna",
        "e-mail": "ímejl", "e-maily": "ímejly", "e-mailu": "ímejlu",
        "home": "houm", "office": "ofis",
        "teambuilding": "tímbilding",
        "Excel": "eksel",
        "pizzu": "picu", "pizza": "pica"
    ]

    static func pronounceable(_ text: String) -> String {
        let trim = CharacterSet(charactersIn: ".,!?;:„“\"”«»…()")
        let words = text
            .replacingOccurrences(of: "___", with: "…")
            .split(separator: " ", omittingEmptySubsequences: false)
            .map { raw -> String in
                let word = String(raw)
                let core = word.trimmingCharacters(in: trim)
                guard let replacement = overrides[core] else { return word }
                return word.replacingOccurrences(of: core, with: replacement)
            }
        return words.joined(separator: " ")
    }
}
