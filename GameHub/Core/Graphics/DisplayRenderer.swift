import Foundation
import Metal
import MetalKit
import UIKit
import Network

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

    private var sharedTextureName: UInt32 = 0
    private var sharedEvent: MTLSharedEvent?
    private var frameSemaphore = DispatchSemaphore(value: 3)

    private var outputSocketPath: String
    private var frameSocketConnection: NWConnection?

    override init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        outputSocketPath = docs.appendingPathComponent("Wine/display.sock").path

        super.init()
        setupMetal()
    }

    private func setupMetal() {
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()

        guard let device = device, let library = device.makeDefaultLibrary() else {
            print("[Display] Metal not available")
            return
        }

        let vertexFunction = library.makeFunction(name: "vertexShader")
        let fragmentFunction = library.makeFunction(name: "fragmentShader")

        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            print("[Display] Failed to create pipeline state: \(error)")
        }

        vertexBuffer = device.makeBuffer(
            bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: []
        )
        texCoordBuffer = device.makeBuffer(
            bytes: texCoordData, length: texCoordData.count * MemoryLayout<Float>.size, options: []
        )

        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.sAddressMode = .clampToEdge
        samplerDescriptor.tAddressMode = .clampToEdge
        samplerState = device?.makeSamplerState(descriptor: samplerDescriptor)

        sharedEvent = MTLSharedEvent()
        sharedEvent?.label = "FrameSync"

        print("[Display] Metal setup complete: \(device.name)")
    }

    func startRendering() {
        isRendering = true
        lastFPSTime = Date()

        DispatchQueue.main.async { [weak self] in
            let displayLink = CADisplayLink(target: self!, selector: #selector(self!.renderFrame))
            displayLink.preferredFramesPerSecond = 60
            displayLink.add(to: .main, forMode: .common)
            self?.displayLink = displayLink
        }
    }

    func stopRendering() {
        isRendering = false
        displayLink?.invalidate()
        displayLink = nil
        frameSocketConnection?.cancel()
        frameSocketConnection = nil
    }

    @objc private func renderFrame() {
        guard isRendering, let drawable = getDrawable() else { return }

        frameSemaphore.wait()

        let commandBuffer = commandQueue?.makeCommandBuffer()
        commandBuffer?.label = "Frame"

        if let texture = texture,
           let renderPassDescriptor = createRenderPassDescriptor(drawable: drawable) {
            let encoder = commandBuffer?.makeRenderCommandEncoder(descriptor: renderPassDescriptor)

            encoder?.setRenderPipelineState(pipelineState!)
            encoder?.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
            encoder?.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)
            encoder?.setFragmentTexture(texture, index: 0)
            encoder?.setFragmentSamplerState(samplerState, index: 0)
            encoder?.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
            encoder?.endEncoding()
        }

        commandBuffer?.present(drawable)
        commandBuffer?.addCompletedHandler { [weak self] _ in
            self?.frameSemaphore.signal()
        }
        commandBuffer?.commit()

        updateFPS()
    }

    private func getDrawable() -> CAMetalDrawable? {
        return nil
    }

    private func createRenderPassDescriptor(drawable: CAMetalDrawable) -> MTLRenderPassDescriptor? {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
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
        guard let device = device else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let newTexture = device.makeTexture(descriptor: descriptor) else { return }

        pixelData.withUnsafeBytes { rawBufferPointer in
            let pointer = rawBufferPointer.bindMemory(to: UInt8.self)
            newTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: pointer.baseAddress!,
                bytesPerRow: width * 4
            )
        }

        DispatchQueue.main.async {
            self.texture = newTexture
            self.resolution = CGSize(width: width, height: height)
        }
    }

    func updateFrameFromBuffer(_ buffer: Data, width: Int, height: Int) {
        guard let device = device else { return }

        let descriptor = MTLTextureDescriptor()
        descriptor.textureType = .type2D
        descriptor.width = width
        descriptor.height = height
        descriptor.pixelFormat = .bgra8Unorm
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared

        guard let newTexture = device.makeTexture(descriptor: descriptor) else { return }

        buffer.withUnsafeBytes { rawBufferPointer in
            let pointer = rawBufferPointer.bindMemory(to: UInt8.self)
            newTexture.replace(
                region: MTLRegionMake2D(0, 0, width, height),
                mipmapLevel: 0,
                withBytes: pointer.baseAddress!,
                bytesPerRow: width * 4
            )
        }

        DispatchQueue.main.async {
            self.texture = newTexture
        }
    }

    func setupDisplaySocket() {
        let params = NWParameters()
        params.allowLocalEndpointReuse = true

        let url = URL(fileURLWithPath: outputSocketPath)
        let endpoint = NWEndpoint.unix(path: url.path)

        frameSocketConnection = NWConnection(to: endpoint, using: params)
        frameSocketConnection?.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[Display] Connected to Wine display socket")
            case .failed(let error):
                print("[Display] Connection failed: \(error)")
            default:
                break
            }
        }
        frameSocketConnection?.start(queue: .global(qos: .userInteractive))
    }

    func receiveFrameData() {
        frameSocketConnection?.receive(minimumIncompleteLength: 1, maximumLength: 1024 * 1024 * 4) {
            [weak self] data, _, isComplete, error in

            if let data = data, data.count > 8 {
                let width = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 0, as: UInt32.self) })
                let height = Int(data.withUnsafeBytes { $0.load(fromByteOffset: 4, as: UInt32.self) })
                let pixelData = data.subdata(in: 8..<data.count)

                self?.updateFrameFromBuffer(pixelData, width: width, height: height)
            }

            if !isComplete && error == nil {
                self?.receiveFrameData()
            }
        }
    }
}
