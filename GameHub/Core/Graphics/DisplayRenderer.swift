import Foundation
import Metal
import MetalKit
import UIKit

class DisplayRenderer: NSObject, ObservableObject {
    @Published var fps: Double = 0
    @Published var isRendering = false
    @Published var resolution: CGSize = .zero

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var texture: MTLTexture?
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    private var texCoordBuffer: MTLBuffer?
    private var samplerState: MTLSamplerState?

    private var frameCount: Int = 0
    private var lastFPSTime: Date = Date()
    private var displayLink: CADisplayLink?

    private let vertexData: [Float] = [
        -1.0, -1.0, 0.0, 1.0,
         1.0, -1.0, 0.0, 1.0,
        -1.0,  1.0, 0.0, 1.0,
         1.0,  1.0, 0.0, 1.0,
    ]

    private let texCoordData: [Float] = [
        0.0, 1.0,
        1.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
    ]

    private var frameSemaphore = DispatchSemaphore(value: 3)

    private var outputSocketPath: String

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputSocketPath = docs.appendingPathComponent("Wine/display.sock").path

        super.init()
        setupMetal()
    }

    private func setupMetal() {
        guard let dev = MTLCreateSystemDefaultDevice() else {
            print("[Display] Metal not available")
            return
        }
        device = dev
        commandQueue = dev.makeCommandQueue()

        guard let library = dev.makeDefaultLibrary() else {
            print("[Display] Failed to load Metal library")
            return
        }

        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try dev.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[Display] Failed to create pipeline state: \(error)")
        }

        vertexBuffer = dev.makeBuffer(
            bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: []
        )
        texCoordBuffer = dev.makeBuffer(
            bytes: texCoordData, length: texCoordData.count * MemoryLayout<Float>.size, options: []
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = dev.makeSamplerState(descriptor: samplerDescriptor)

        print("[Display] Metal setup complete: \(dev.name)")
    }

    func startRendering() {
        isRendering = true
        lastFPSTime = Date()

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            let displayLink = CADisplayLink(target: self, selector: #selector(self.renderFrame))
            displayLink.preferredFramesPerSecond = 60
            displayLink.add(to: .main, forMode: .common)
            self.displayLink = displayLink
        }
    }

    func stopRendering() {
        isRendering = false
        displayLink?.invalidate()
        displayLink = nil
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
            DispatchQueue.main.async {
                self.fps = Double(self.frameCount) / elapsed
            }
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

        DispatchQueue.main.async {
            self.texture = newTexture
            self.resolution = CGSize(width: width, height: height)
        }
    }

    func updateFrameFromBuffer(_ buffer: Data, width: Int, height: Int) {
        updateFrame(buffer, width: width, height: height)
    }
}
