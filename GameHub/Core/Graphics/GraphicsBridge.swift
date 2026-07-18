import Foundation
import Metal
import MetalKit

class GraphicsBridge {
    static let shared = GraphicsBridge()

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var isInitialized = false

    struct GraphicsConfig {
        var useVulkan: Bool = true
        var useMoltenVK: Bool = true
        var useDXVK: Bool = true
        var useVKD3D: Bool = true
        var useVirGL: Bool = false
        var useTurnip: Bool = false
        var useZink: Bool = false
        var useVortek: Bool = true
        var gpuDriver: GPUDriver = .moltenVK
        var maxFrameRate: Int = 60
        var vsync: Bool = true
        var resolutionScale: Float = 1.0
        var anisotropicFiltering: Int = 4
        var msaa: Int = 0
        var frameInterpolation: Bool = false
        var hdrOutput: Bool = false
        var showFPS: Bool = true
        var showGPUInfo: Bool = false
        var shaderCacheSize: Int = 512
        var textureCacheSize: Int = 1024
    }

    enum GPUDriver: String, CaseIterable {
        case moltenVK = "moltenvk"
        case turnip = "turnip"
        case virgl = "virgl"
        case zink = "zink"
        case vortek = "vortek"
        case gladio = "gladio"

        var displayName: String {
            switch self {
            case .moltenVK: return "MoltenVK (Vulkan→Metal)"
            case .turnip: return "Turnip (Adreno)"
            case .virgl: return "VirGL (OpenGL)"
            case .zink: return "Zink (OpenGL→Vulkan)"
            case .vortek: return "Vortek (Custom)"
            case .gladio: return "Gladio (Custom)"
            }
        }
    }

    private var config = GraphicsConfig()

    func initialize() {
        guard !isInitialized else { return }

        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()

        if let device = device {
            print("[Graphics] Metal device: \(device.name)")
            print("[Graphics] GPU family: \(device.supportsFamily(.apple7) ? "Apple 7+" : "Apple 6 or earlier")")
            print("[Graphics] Max threadgroup memory: \(device.maxThreadgroupMemoryLength) bytes")
            print("[Graphics] Max buffer size: \(device.maxBufferLength) bytes")
        } else {
            print("[Graphics] WARNING: Metal not available!")
        }

        setupMoltenVK()
        setupEnvironment()
        isInitialized = true
        print("[Graphics] Initialized successfully")
    }

    private func setupMoltenVK() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let moltenVKPath = documentsPath.appendingPathComponent("Graphics")

        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: moltenVKPath.path) {
            try? fileManager.createDirectory(at: moltenVKPath, withIntermediateDirectories: true)
        }

        setenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1)
        setenv("MVK_CONFIG_PRESENT_WITHIMUMEDIATE_SWAPCHAIN", "1", 1)
        setenv("MVK_CONFIG_MAX_ACTIVE_RENDER_PASSES", "1", 1)
        setenv("MVK_CONFIG_MAX_SAMPLER_PER_PIPELINE_STATE_COUNT", "16", 1)
    }

    private func setupEnvironment() {
        setenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1)
        setenv("MVK_CONFIG_PREFER_STORE_STORE_APPLE", "1", 1)
        setenv("MVK_CONFIG_IMAGELESS_FRAMEBUFFER_ALLOW", "1", 1)

        if config.useDXVK {
            setenv("DXVK_LOG_LEVEL", "none", 1)
            setenv("DXVK_FRAME_RATE", "\(config.maxFrameRate)", 1)
            setenv("DXVK_HUD", config.showFPS ? "fps" : "none", 1)
        }

        if config.useVKD3D {
            setenv("VKD3D_CONFIG", "dxr", 1)
            setenv("VKD3D_FEATURE_LEVEL", "12_1", 1)
        }
    }

    func getGPUInfo() -> [String: Any] {
        guard let device = device else {
            return ["error": "No Metal device"]
        }

        var info: [String: Any] = [
            "name": device.name,
            "registryID": device.registryID,
            "maxThreadgroupMemoryLength": device.maxThreadgroupMemoryLength,
            "maxBufferSize": device.maxBufferLength,
            "maxTextureWidth": device.supportsFamily(.apple7) ? 16384 : 8192,
            "maxTextureHeight": device.supportsFamily(.apple7) ? 16384 : 8192,
            "supportsRaytracing": device.supportsRaytracing(),
            "supportsBarycentricCoords": device.supportsBarycentricCoords(),
            "supportsCounterSampling": device.supportsCounterSampling(.shuffled),
            "hasUnifiedMemory": device.hasUnifiedMemory,
            "maxThreadgroupMemoryLengthBytes": device.maxThreadgroupMemoryLength,
        ]

        if let gpuInfo = getGPUInfoFromSystem() {
            info.merge(gpuInfo) { _, new in new }
        }

        return info
    }

    private func getGPUInfoFromSystem() -> [String: Any]? {
        var info: [String: Any] = [:]
        var size: size_t = 0
        sysctlbyname("hw.memsize", nil, &size, nil, 0)
        info["systemMemory"] = size

        var cpuCount: size_t = 0
        var cpuCountSize = MemoryLayout<size_t>.size
        sysctlbyname("hw.ncpu", &cpuCount, &cpuCountSize, nil, 0)
        info["cpuCount"] = cpuCount

        return info
    }

    func setupDXVKEnvironment(containerPath: String) {
        let dxvkConfig = """
        [dxvk]
        dxvk.numAsyncThreads = 2
        dxvk.numCompilerThreads = 4
        dxvk.enableAsync = true
        dxvk.hud = \(config.showFPS ? "fps,frametimes" : "none")
        dxvk.maxFrameRate = \(config.maxFrameRate)
        dxvk.syncInterval = \(config.vsync ? 1 : 0)

        [d3d9]
        d3d9.presentInterval = \(config.vsync ? 1 : 0)
        d3d9.forceSamplerTypeConstants = false
        d3d9.floatEmulation = strict
        """

        let configPath = containerPath + "/dxvk.conf"
        try? dxvkConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    func setupVKD3DEnvironment(containerPath: String) {
        let vkd3dConfig = """
        [VKD3D]
        vkd3d.config_files = \(containerPath)/vkd3d.cfg
        """

        let configPath = containerPath + "/vkd3d.ini"
        try? vkd3dConfig.write(toFile: configPath, atomically: true, encoding: .utf8)
    }

    func createMetalView() -> MTKView? {
        guard let device = device else { return nil }
        let view = MTKView(frame: .zero, device: device)
        view.preferredFramesPerSecond = config.maxFrameRate
        view.enableSetNeedsDisplay = true
        view.isPaused = false
        view.colorPixelFormat = .bgra10_XR
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        return view
    }

    func updateConfig(_ updater: (inout GraphicsConfig) -> Void) {
        updater(&config)
        setupEnvironment()
    }

    func getSupportedFeatures() -> [String: Bool] {
        guard let device = device else { return [:] }

        var features: [String: Bool] = [:]
        features["raytracing"] = device.supportsRaytracing()
        features["barycentricCoords"] = device.supportsBarycentricCoords()
        features["appleFamily"] = true
        features["apple7"] = device.supportsFamily(.apple7)
        features["apple6"] = device.supportsFamily(.apple6)
        features["macFamily1"] = device.supportsFamily(.mac1)
        features["commonFamily3"] = device.supportsFamily(.common3)

        return features
    }
}
