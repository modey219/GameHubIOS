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
    private let socketLock = NSLock()
    private var audioThread: DispatchQueue?
    private var isServerRunning = false
    private var socketPath: String

    var audioBuffer = Data()
    var bufferLock = NSLock()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
        DispatchQueue.main.async { self.isPlaying = true }
    }

    func stopAudio() {
        DispatchQueue.main.async { self.isPlaying = false }
        isServerRunning = false
        socketLock.lock()
        let cs = clientSocket
        let ss = serverSocket
        clientSocket = -1
        serverSocket = -1
        socketLock.unlock()
        if cs >= 0 { close(cs) }
        if ss >= 0 { close(ss) }
        if let q = audioQueue { AudioQueueStop(q, true); AudioQueueDispose(q, true); audioQueue = nil }
        try? FileManager.default.removeItem(atPath: socketPath)
    }

    private func startPosixSocketServer() {
        isServerRunning = true
        unlink(socketPath)

        let ss = socket(AF_UNIX, SOCK_STREAM, 0)
        guard ss >= 0 else { return }
        socketLock.lock()
        serverSocket = ss
        socketLock.unlock()

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
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(ss, $0, addrLen) }
        }
        guard bindResult == 0 else { close(ss); socketLock.lock(); serverSocket = -1; socketLock.unlock(); return }
        guard listen(ss, 1) == 0 else { close(ss); socketLock.lock(); serverSocket = -1; socketLock.unlock(); return }

        while isServerRunning {
            socketLock.lock()
            let currentSS = serverSocket
            socketLock.unlock()
            guard currentSS >= 0 else { break }
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(currentSS, $0, &clientLen) }
            }
            if client >= 0 {
                socketLock.lock()
                clientSocket = client
                socketLock.unlock()
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
                if audioBuffer.count < 1024 * 1024 {
                    audioBuffer.append(contentsOf: buffer.prefix(n))
                } else {
                    audioBuffer.removeAll()
                }
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
