import Foundation
import AVFoundation

class AudioManager: ObservableObject {
    @Published var isPlaying = false
    @Published var volume: Float = 1.0
    @Published var audioDriver: AudioDriver = .pulseaudio

    enum AudioDriver: String, CaseIterable {
        case pulseaudio = "pulseaudio"
        case coreaudio = "coreaudio"

        var displayName: String {
            switch self {
            case .pulseaudio: return "PulseAudio"
            case .coreaudio: return "Core Audio (Native)"
            }
        }
    }

    private var audioEngine: AVAudioEngine?
    private var audioSession: AVAudioSession?

    init() {
        setupAudioSession()
    }

    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .gameChat, options: [.mixWithOthers, .allowBluetooth])
            try audioSession?.setActive(true)
            print("[Audio] Audio session configured")
        } catch {
            print("[Audio] Failed to setup audio session: \(error)")
        }
    }

    func configureAudioForWine() {
        switch audioDriver {
        case .pulseaudio:
            setenv("PULSE_SERVER", "127.0.0.1", 1)
            setenv("PULSE_SINK", "output", 1)
            setenv("PULSE_SOURCE", "input", 1)
            startPulseAudioServer()

        case .coreaudio:
            setenv("AUDIODEV", "/dev/dsp", 1)
            setenv("AUDIO_DRIVER", "coreaudio", 1)
        }

        setenv("WINEAUDIO_DRIVER", audioDriver.rawValue, 1)
    }

    private func startPulseAudioServer() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pulseaudio")
        process.arguments = [
            "--daemonize=false",
            "--exit-idle-time=-1",
            "--load", "module-native-protocol-unix",
            "--load", "module-detect",
        ]

        let env = ProcessInfo.processInfo.environment
        process.environment = env

        do {
            try process.run()
            print("[Audio] PulseAudio server started")
        } catch {
            print("[Audio] Failed to start PulseAudio: \(error)")
        }
    }

    func stopAudio() {
        audioSession?.isOtherAudioPlaying == false ? try? audioSession?.setActive(false) : nil
        isPlaying = false
    }

    func setVolume(_ vol: Float) {
        volume = max(0, min(1, vol))
        setenv("WINE_VOLUME", "\(Int(volume * 100))", 1)
    }

    func getAudioLatency() -> Double {
        return 0.02
    }

    func getAudioBufferSize() -> Int {
        return 1024
    }

    func getSupportedSampleRates() -> [Int] {
        return [22050, 44100, 48000, 96000]
    }

    func configureAudioForGame(sampleRate: Int = 44100, channels: Int = 2, bufferSize: Int = 1024) {
        do {
            try audioSession?.setPreferredSampleRate(Double(sampleRate))
            try audioSession?.setPreferredIOBufferDuration(Double(bufferSize) / Double(sampleRate))
            print("[Audio] Configured for \(sampleRate)Hz, \(channels)ch, buffer=\(bufferSize)")
        } catch {
            print("[Audio] Configuration failed: \(error)")
        }
    }
}
