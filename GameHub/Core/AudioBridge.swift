import Foundation
import AVFoundation
import AudioToolbox

class AudioBridge: ObservableObject {
    static let shared = AudioBridge()

    @Published var isPlaying = false
    @Published var volume: Float = 1.0
    @Published var latency: Double = 0

    private var audioQueue: AudioQueueRef?
    private var audioSession: AVAudioSession?
    private var format: AudioStreamBasicDescription?
    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var audioThread: DispatchQueue?
    private var isServerRunning = false
    private var socketPath: String

    var audioBuffer = Data()
    var bufferLock = NSLock()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        socketPath = docs.appendingPathComponent("Wine/audio.sock").path
        setupAudioSession()
        format = AudioStreamBasicDescription(
            mSampleRate: 44100, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4,
            mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0
        )
    }

    private func setupAudioSession() {
        do {
            audioSession = AVAudioSession.sharedInstance()
            try audioSession?.setCategory(.playback, mode: .gameChat, options: [.mixWithOthers])
            try audioSession?.setPreferredSampleRate(44100)
            try audioSession?.setActive(true)
        } catch {
            print("[Audio] Session setup failed: \(error)")
        }
    }

    func startAudioServer() {
        audioThread = DispatchQueue(label: "com.gamehub.audio", qos: .userInteractive)
        audioThread?.async { [weak self] in self?.startPosixSocketServer() }
        startAudioQueue()
        isPlaying = true
    }

    func stopAudio() {
        isPlaying = false
        isServerRunning = false
        if let q = audioQueue { AudioQueueStop(q, true); AudioQueueDispose(q, true); audioQueue = nil }
        if clientSocket >= 0 { close(clientSocket); clientSocket = -1 }
        if serverSocket >= 0 { close(serverSocket); serverSocket = -1 }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func startPosixSocketServer() {
        isServerRunning = true
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLen = min(socketPath.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        socketPath.withCString { cPath in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                UnsafeMutableRawPointer(ptr).copyMemory(from: cPath, byteCount: pathLen)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverSocket, $0, addrLen) }
        }
        guard bindResult == 0 else { close(serverSocket); serverSocket = -1; return }
        guard listen(serverSocket, 1) == 0 else { close(serverSocket); serverSocket = -1; return }

        while isServerRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(serverSocket, $0, &clientLen) }
            }
            if client >= 0 {
                clientSocket = client
                receiveAudioData()
            }
        }
    }

    private func receiveAudioData() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while clientSocket >= 0 && isServerRunning {
            let n = recv(clientSocket, &buffer, buffer.count, 0)
            if n > 0 {
                bufferLock.lock()
                audioBuffer.append(contentsOf: buffer.prefix(n))
                bufferLock.unlock()
            } else if n == 0 || (n < 0 && errno != EINTR) { break }
        }
    }

    private func startAudioQueue() {
        guard var fmt = format else { return }
        var queue: AudioQueueRef?
        let status = AudioQueueNewOutput(&fmt, audioQueueCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &queue)
        guard status == noErr, let q = queue else { return }
        audioQueue = q
        let bufSize = UInt32(1024) * fmt.mBytesPerFrame
        for _ in 0..<3 {
            var buf: AudioQueueBufferRef?
            AudioQueueAllocateBuffer(q, bufSize, &buf)
            if let b = buf { AudioQueueEnqueueBuffer(q, b, 0, nil) }
        }
        AudioQueueStart(q, nil)
    }

    func setVolume(_ vol: Float) {
        volume = max(0, min(1, vol))
        if let q = audioQueue { AudioQueueSetParameter(q, kAudioQueueParam_Volume, volume) }
    }
}

private func audioQueueCallback(inUserData: UnsafeMutableRawPointer?, inAQ: AudioQueueRef, inBuffer: AudioQueueBufferRef) {
    guard let userData = inUserData else { return }
    let bridge = Unmanaged<AudioBridge>.fromOpaque(userData).takeUnretainedValue()
    bridge.bufferLock.lock()
    let available = bridge.audioBuffer.count
    let requested = Int(inBuffer.pointee.mAudioDataByteSize)
    if available >= requested {
        bridge.audioBuffer.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), count: requested)
        bridge.audioBuffer.removeFirst(requested)
        bridge.bufferLock.unlock()
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    } else {
        if available > 0 {
            bridge.audioBuffer.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), count: available)
            bridge.audioBuffer.removeAll()
        }
        bridge.bufferLock.unlock()
        memset(inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), 0, requested)
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    }
}
