import AVFoundation
import Speech

/// Распознавание словацкой речи для упражнений «Произнесите вслух».
final class SpeechRecognizer: ObservableObject {
    @Published var transcript = ""
    @Published var isRecording = false
    @Published var error: String?

    private static let locale = Locale(identifier: "sk-SK")
    private let recognizer = SFSpeechRecognizer(locale: SpeechRecognizer.locale)
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var autoStop: DispatchWorkItem?

    /// Поддерживает ли устройство распознавание словацкого.
    static var isSupported: Bool {
        SFSpeechRecognizer(locale: locale)?.isAvailable ?? false
    }

    func toggle() {
        isRecording ? stop() : start()
    }

    func start() {
        error = nil
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                guard status == .authorized else {
                    self.error = "Нет доступа к распознаванию речи. Разрешите его в Настройках → Slovíčko."
                    return
                }
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    DispatchQueue.main.async {
                        if granted {
                            self.begin()
                        } else {
                            self.error = "Нет доступа к микрофону. Разрешите его в Настройках → Slovíčko."
                        }
                    }
                }
            }
        }
    }

    private func begin() {
        guard let recognizer, recognizer.isAvailable else {
            error = "Распознавание словацкого сейчас недоступно (нужен интернет)."
            return
        }
        stopEngine()
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try session.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            self.error = "Не удалось включить микрофон."
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            self.error = "Не удалось начать запись."
            stopEngine()
            return
        }

        transcript = ""
        isRecording = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal { self.stop() }
                }
                if error != nil && self.isRecording {
                    self.stop()
                }
            }
        }

        // Не держим микрофон дольше 10 секунд.
        let work = DispatchWorkItem { [weak self] in self?.stop() }
        autoStop = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: work)
    }

    func stop() {
        autoStop?.cancel()
        autoStop = nil
        stopEngine()
        request?.endAudio()
        request = nil
        task?.finish()
        task = nil
        if isRecording {
            isRecording = false
        }
        // Возвращаем режим воспроизведения для озвучки.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    }

    private func stopEngine() {
        if engine.isRunning {
            engine.stop()
        }
        engine.inputNode.removeTap(onBus: 0)
    }
}
