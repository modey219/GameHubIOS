import Foundation
import AVFoundation
import AudioToolbox
import os

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
    private var _bufferLock = os_unfair_lock()
    fileprivate func bufferLock() { os_unfair_lock_lock(&_bufferLock) }
    fileprivate func bufferUnlock() { os_unfair_lock_unlock(&_bufferLock) }

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
        socketLock.lock()
        isServerRunning = false
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
        socketLock.lock()
        isServerRunning = true
        socketLock.unlock()
        unlink(socketPath)

        let ss = socket(AF_UNIX, SOCK_STREAM, 0)
        guard ss >= 0 else { return }
        socketLock.lock()
        serverSocket = ss
        socketLock.unlock()

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLen = min(socketPath.utf8.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
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

        while true {
            socketLock.lock()
            let running = isServerRunning
            let currentSS = serverSocket
            socketLock.unlock()
            guard running, currentSS >= 0 else { break }
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
        var buffer = [UInt8](repeating: 0, count: 32768)
        while true {
            socketLock.lock()
            let running = isServerRunning
            let cs = clientSocket
            socketLock.unlock()
            guard running, cs >= 0 else { break }
            let n = recv(cs, &buffer, buffer.count, 0)
            if n > 0 {
                bufferLock()
                if audioBuffer.count < 512 * 1024 {
                    audioBuffer.append(contentsOf: buffer.prefix(n))
                } else {
                    let dropBytes = min(audioBuffer.count, 32768)
                    audioBuffer.removeFirst(dropBytes)
                    audioBuffer.append(contentsOf: buffer.prefix(n))
                }
                bufferUnlock()
            } else if n == 0 || (n < 0 && errno != EINTR) { break }
        }
    }

    private func startAudioQueue() {
        guard var fmt = format else { return }
        var queue: AudioQueueRef?
        let status = AudioQueueNewOutput(&fmt, audioQueueCallback, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &queue)
        guard status == noErr, let q = queue else { return }
        audioQueue = q
        let bufSize = UInt32(512) * fmt.mBytesPerFrame
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
    bridge.bufferLock()
    let available = bridge.audioBuffer.count
    let requested = Int(inBuffer.pointee.mAudioDataByteSize)
    if available >= requested {
        bridge.audioBuffer.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), count: requested)
        bridge.audioBuffer.removeFirst(requested)
        bridge.bufferUnlock()
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    } else {
        if available > 0 {
            bridge.audioBuffer.copyBytes(to: inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), count: available)
            bridge.audioBuffer.removeAll()
        }
        bridge.bufferUnlock()
        memset(inBuffer.pointee.mAudioData.assumingMemoryBound(to: UInt8.self), 0, requested)
        AudioQueueEnqueueBuffer(inAQ, inBuffer, 0, nil)
    }
}
