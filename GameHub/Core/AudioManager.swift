import Foundation
import AVFoundation

class AudioManager: ObservableObject {
    @Published var isPlaying = false
    @Published var volume: Float = 1.0
    @Published var audioDriver: AudioDriver = .coreaudio

    enum AudioDriver: String, CaseIterable {
        case coreaudio = "coreaudio"
        case pulseaudio = "pulseaudio"

        var displayName: String {
            switch self {
            case .coreaudio: return "Core Audio (Native)"
            case .pulseaudio: return "PulseAudio (Requires setup)"
            }
        }
    }

    private var audioSession: AVAudioSession?

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .gameChat, options: [.mixWithOthers])
            try audioSession?.setActive(true)
        } catch {
            print("[Audio] Session setup failed: \(error)")
        }
    }

    func configureForWine() {
        switch audioDriver {
        case .coreaudio:
            safeSetenv("AUDIODEV", "/dev/dsp", 1)
            safeSetenv("AUDIO_DRIVER", "coreaudio", 1)
        case .pulseaudio:
            safeSetenv("PULSE_SERVER", "127.0.0.1", 1)
        }
    }

    func stopAudio() {
        try? audioSession?.setActive(false)
        isPlaying = false
    }

    func setVolume(_ vol: Float) {
        volume = max(0, min(1, vol))
    }
}
