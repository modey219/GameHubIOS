import Foundation
import Metal
import MetalKit

class DisplayRenderer: NSObject, ObservableObject {
    @Published var fps: Double = 0
    @Published var isRendering = false
    @Published var resolution: CGSize = .zero

    private(set) var currentTexture: MTLTexture?
    private var textureLock = NSLock()

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?

    private var frameCount: Int = 0
    private var lastFPSTime: Date = Date()
    private var displayLink: CADisplayLink?

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
            let link = CADisplayLink(target: self, selector: #selector(self.renderFrame))
            link.preferredFramesPerSecond = 60
            link.add(to: .main, forMode: .common)
            self.displayLink = link
        }
    }

    func stopRendering() {
        isRendering = false
        DispatchQueue.main.async { [weak self] in
            self?.displayLink?.invalidate()
            self?.displayLink = nil
        }
    }

    @objc private func renderFrame() {
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
        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let newTexture = dev.makeTexture(descriptor: descriptor) else { return }
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
        currentTexture = newTexture
        textureLock.unlock()

        DispatchQueue.main.async {
            self.resolution = CGSize(width: width, height: height)
        }
    }
}
