import AVFoundation

/// Короткие звуки интерфейса (файлы из Resources/Sounds, синтезированы tools/make_sounds.py).
final class SoundFX {
    static let shared = SoundFX()

    enum Effect: String, CaseIterable {
        case correct, wrong, complete, pop, combo
    }

    var enabled = true
    private var players: [Effect: AVAudioPlayer] = [:]

    private init() {
        for effect in Effect.allCases {
            guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "wav"),
                  let player = try? AVAudioPlayer(contentsOf: url) else { continue }
            player.volume = 0.8
            player.prepareToPlay()
            players[effect] = player
        }
    }

    func play(_ effect: Effect) {
        guard enabled, let player = players[effect] else { return }
        let session = AVAudioSession.sharedInstance()
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        }
        try? session.setActive(true)
        player.currentTime = 0
        player.play()
    }
}
