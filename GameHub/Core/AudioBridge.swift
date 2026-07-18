import Foundation
import AVFoundation
import AudioToolbox
import Network

class AudioBridge: ObservableObject {
    static let shared = AudioBridge()

    @Published var isPlaying = false
    @Published var volume: Float = 1.0
    @Published var sampleRate: Double = 44100
    @Published var bufferSize: Int = 1024
    @Published var latency: Double = 0

    private var audioQueue: AudioQueueRef?
    private var audioSession: AVAudioSession?

    private var socketPath: String
    private var audioSocketConnection: NWConnection?
    private var audioBuffer: Data = Data()
    private var bufferLock = NSLock()
    private var audioThread: DispatchQueue?

    private var format: AudioStreamBasicDescription?

    struct AudioHeader {
        var sampleRate: UInt32
        var channels: UInt32
        var bitsPerSample: UInt32
        var bytesPerFrame: UInt32
        var frameCount: UInt32
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        socketPath = docs.appendingPathComponent("Wine/audio.sock").path

        setupAudioSession()
        setupFormat()
    }

    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(
                .playback,
                mode: .gameChat,
                options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker]
            )
            try audioSession?.setPreferredSampleRate(44100)
            try audioSession?.setPreferredIOBufferDuration(Double(bufferSize) / 44100)
            try audioSession?.setActive(true)
            print("[Audio] Session configured: 44100Hz, \(bufferSize) samples buffer")
        } catch {
            print("[Audio] Session setup failed: \(error)")
        }
    }

    private func setupFormat() {
        format = AudioStreamBasicDescription(
            mSampleRate: 44100,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 16,
            mReserved: 0
        )
    }

    func startAudioServer() {
        audioThread = DispatchQueue(label: "com.gamehub.audio", qos: .userInteractive)
        audioThread?.async { [weak self] in
            self?.setupAudioSocket()
        }
        startAudioQueue()
        isPlaying = true
        print("[Audio] Server started")
    }

    func stopAudio() {
        isPlaying = false
        if let queue = audioQueue {
            AudioQueueStop(queue, true)
            AudioQueueDispose(queue, true)
            audioQueue = nil
        }
        audioSocketConnection?.cancel()
        audioSocketConnection = nil
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func setupAudioSocket() {
        let params = NWParameters()
        params.allowLocalEndpointReuse = true

        let url = URL(fileURLWithPath: socketPath)
        let endpoint = NWEndpoint.unix(path: url.path)

        do {
            let listener = try NWListener(using: params, on: endpoint)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleAudioConnection(connection)
            }
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[Audio] Socket server ready")
                case .failed(let error):
                    print("[Audio] Socket server failed: \(error)")
                default:
                    break
                }
            }
            listener.start(queue: audioThread!)
        } catch {
            print("[Audio] Failed to create socket: \(error)")
        }
    }

    private func handleAudioConnection(_ connection: NWConnection) {
        audioSocketConnection = connection
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Audio] Wine audio connected")
                self.receiveAudioData()
            case .failed(let error):
                print("[Audio] Wine audio disconnected: \(error)")
            default:
                break
            }
        }
        connection.start(queue: audioThread!)
    }

    private func receiveAudioData() {
        audioSocketConnection?.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65536
        ) { [weak self] data, _, isComplete, error in

            if let data = data, !data.isEmpty {
                self?.bufferLock.lock()
                self?.audioBuffer.append(data)
                self?.bufferLock.unlock()
            }

            if !isComplete && error == nil {
                self?.receiveAudioData()
            }
        }
    }

    private func startAudioQueue() {
        guard var fmt = format else { return }

        var queue: AudioQueueRef?
        let status = AudioQueueNewOutput(
            &fmt,
            audioQueueCallback,
            Unmanaged.passUnretained(self).toOpaque(),
            nil,
            nil,
            0,
            &queue
        )

        guard status == noErr, let queue = queue else {
            print("[Audio] Failed to create audio queue: \(status)")
            return
        }

        audioQueue = queue

        let bufferByteSize = bufferSize * fmt.mBytesPerFrame
        for _ in 0..<3 {
            var buffer: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(queue, UInt32(bufferByteSize), &buffer)
            if let buffer = buffer {
                AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
            }
        }

        AudioQueueStart(queue, nil)
    }

    func setVolume(_ vol: Float) {
        volume = max(0, min(1, vol))
        if let queue = audioQueue {
            AudioQueueSetParameter(queue, kAudioQueueParam_Volume, volume)
        }
    }

    func configureForGame(sampleRate: Double = 44100, channels: Int = 2, buffer: Int = 1024) {
        self.sampleRate = sampleRate
        self.bufferSize = buffer

        format = AudioStreamBasicDescription(
            mSampleRate: sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 2),
            mFramesPerPacket: 1,
            mBytesPerFrame: UInt32(channels * 2),
            mChannelsPerFrame: UInt32(channels),
            mBitsPerChannel: 16,
            mReserved: 0
        )

        do {
            try audioSession?.setPreferredSampleRate(sampleRate)
            try audioSession?.setPreferredIOBufferDuration(Double(buffer) / sampleRate)
        } catch {
            print("[Audio] Reconfiguration failed: \(error)")
        }
    }

    func getSupportedSampleRates() -> [Double] {
        return [22050, 44100, 48000, 96000]
    }

    func getAudioStats() -> (latency: Double, underruns: Int, sampleRate: Double) {
        return (latency, 0, sampleRate)
    }
}

private func audioQueueCallback(
    inUserData: UnsafeMutableRawPointer?,
    inAQ: AudioQueueRef,
    inBuffer: AudioQueueBufferRef
) {
    guard let userData = inUserData else { return }

    let bridge = Unmanaged<AudioBridge>.fromOpaque(userData).takeUnretainedValue()

    bridge.bufferLock.lock()
    let availableBytes = bridge.audioBuffer.count
    let requestedBytes = Int(inBuffer.pointee.mAudioDataByteSize)

    if availableBytes >= requestedBytes {
        let dataToWrite = bridge.audioBuffer.prefix(requestedBytes)
        dataToWrite.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), count: requestedBytes)
        bridge.audioBuffer.removeFirst(requestedBytes)
        bridge.bufferLock.unlock()

        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    } else {
        if availableBytes > 0 {
            bridge.audioBuffer.copyBytes(
                to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self),
                count: availableBytes
            )
            bridge.audioBuffer.removeAll()
        }
        bridge.bufferLock.unlock()

        let silence = inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self)
        let remaining = requestedBytes - min(availableBytes, requestedBytes)
        memset(silence.advanced(by: availableBytes), 0, remaining)

        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    }
}
