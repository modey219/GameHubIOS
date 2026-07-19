import Foundation
import Metal

class GraphicsBridge {
    static let shared = GraphicsBridge()

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var isInitialized = false

    enum GPUDriver: String, CaseIterable {
        case moltenVK = "moltenvk"
        case turnip = "turnip"
        case virgl = "virgl"
        case zink = "zink"

        var displayName: String {
            switch self {
            case .moltenVK: return "MoltenVK (Vulkan→Metal)"
            case .turnip: return "Turnip (Adreno)"
            case .virgl: return "VirGL (OpenGL)"
            case .zink: return "Zink (OpenGL→Vulkan)"
            }
        }
    }

    func initialize() {
        guard !isInitialized else { return }
        device = MTLCreateSystemDefaultDevice()
        commandQueue = device?.makeCommandQueue()
        setupEnvironment()
        isInitialized = true
        if let device = device {
            print("[Graphics] Metal: \(device.name)")
        }
    }

    private func setupEnvironment() {
        safeSetenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        safeSetenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1)
        safeSetenv("DXVK_LOG_LEVEL", "none", 1)
        safeSetenv("DXVK_HUD", "fps", 1)
        safeSetenv("VKD3D_CONFIG", "dxr", 1)
    }

    func getGPUInfo() -> [String: Any] {
        guard let device = device else { return ["error": "No Metal device"] }
        return [
            "name": device.name,
            "maxBufferSize": device.maxBufferLength,
            "hasUnifiedMemory": device.hasUnifiedMemory,
            "supportsApple7": device.supportsFamily(.apple7),
            "supportsApple6": device.supportsFamily(.apple6),
        ]
    }

    func setupDXVKEnvironment(containerPath: String) {
        let config = "[dxvk]\ndxvk.enableAsync = true\ndxvk.hud = fps\n"
        try? config.write(toFile: containerPath + "/dxvk.conf", atomically: true, encoding: .utf8)
    }
}
