import Foundation
import Metal
import MetalKit

private class DisplayLinkProxy {
    weak var renderer: DisplayRenderer?
    init(_ renderer: DisplayRenderer) { self.renderer = renderer }
    @objc func renderFrame() { renderer?.onRenderFrame() }
}

class DisplayRenderer: NSObject, ObservableObject {
    @Published var fps: Double = 0
    @Published var isRendering = false
    @Published var resolution: CGSize = .zero

    private(set) var currentTexture: MTLTexture?
    private var textureLock = NSLock()

    private(set) var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var texturePool: [MTLTexture] = []
    private let maxTexturePoolSize = 4
    private var lastTextureWidth = 0
    private var lastTextureHeight = 0

    private var frameCount: Int = 0
    private var lastFPSTime: Date = Date()
    private var displayLink: CADisplayLink?
    private var proxy: DisplayLinkProxy?

    override init() {
        super.init()
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
    }

    deinit {
        stopRendering()
    }

    func startRendering() {
        isRendering = true
        lastFPSTime = Date()
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let p = DisplayLinkProxy(self)
            self.proxy = p
            let link = CADisplayLink(target: p, selector: #selector(DisplayLinkProxy.renderFrame))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    func stopRendering() {
        isRendering = false
        DispatchQueue.main.async {
            self.displayLink?.invalidate()
            self.displayLink = nil
            self.proxy = nil
        }
    }

    func onRenderFrame() {
        guard isRendering else { return }
        updateFPS()
    }

    private func updateFPS() {
        frameCount += 1
        let now = Date()
        let elapsed = now.timeIntervalSince(lastFPSTime)
        if elapsed >= 1.0 {
            let currentFps = Double(frameCount) / elapsed
            DispatchQueue.main.async { self.fps = currentFps }
            frameCount = 0
            lastFPSTime = now
        }
    }

    func updateFrame(_ pixelData: Data, width: Int, height: Int) {
        guard let dev = device else { return }

        textureLock.lock()
        var tex: MTLTexture?
        if width == lastTextureWidth && height == lastTextureHeight, !texturePool.isEmpty {
            tex = texturePool.removeFirst()
        }
        textureLock.unlock()

        if tex == nil {
            let descriptor = MTLTextureDescriptor()
            descriptor.textureType = .type2D
            descriptor.width = width
            descriptor.height = height
            descriptor.pixelFormat = .bgra8Unorm
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            tex = dev.makeTexture(descriptor: descriptor)
            textureLock.lock()
            lastTextureWidth = width
            lastTextureHeight = height
            textureLock.unlock()
        }

        guard let newTexture = tex else { return }
        pixelData.withUnsafeBytes { rawBufferPointer in
            guard let pointer = rawBufferPointer.baseAddress else { return }
            newTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: pointer,
                bytesPerRow: width * 4
            )
        }

        textureLock.lock()
        let oldTexture = currentTexture
        currentTexture = newTexture
        if let old = oldTexture, old.width == width && old.height == height, texturePool.count < maxTexturePoolSize {
            texturePool.append(old)
        }
        textureLock.unlock()

        DispatchQueue.main.async {
            self.resolution = CGSize(width: width, height: height)
        }
    }
}
