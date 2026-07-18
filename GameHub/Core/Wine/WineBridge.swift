import Foundation

class WineBridge {
    static let shared = WineBridge()

    private var isInitialized = false
    private var winePrefix: String = ""
    private var wineBinaryPath: String = ""

    struct WineConfig {
        var wineVersion: String = "wine-9.0"
        var useGLSL: Bool = true
        var useCSMT: Bool = true
        var useStrictDrawOrdering: Bool = false
        var useGL: Bool = false
        var useVulkan: Bool = true
        var useDXVK: Bool = true
        var useVKD3D: Bool = true
        var renderer: Renderer = .vulkan
        var audioDriver: AudioDriver = .pulseaudio
        var sandboxMode: Bool = true
        var windowDecorations: Bool = false
        var virtualDesktop: Bool = false
        var virtualDesktopSize: String = "1024x768"
        var dpi: Int = 96
        var fontSmoothing: Bool = false
        var debugChannels: [String] = []
    }

    enum Renderer: String, CaseIterable {
        case vulkan = "vulkan"
        case gl = "opengl"
        case glsl = "glsl"
        case vkd3d = "vkd3d"
        case dxvk = "dxvk"

        var displayName: String {
            switch self {
            case .vulkan: return "Vulkan (via MoltenVK)"
            case .gl: return "OpenGL ES"
            case .glsl: return "GLSL (WineD3D)"
            case .vkd3d: return "VKD3D (DX12)"
            case .dxvk: return "DXVK (DX11)"
            }
        }
    }

    enum AudioDriver: String, CaseIterable {
        case pulseaudio = "pulseaudio"
        case coreaudio = "coreaudio"
        case alsa = "alsa"

        var displayName: String {
            switch self {
            case .pulseaudio: return "PulseAudio"
            case .coreaudio: return "Core Audio"
            case .alsa: return "ALSA"
            }
        }
    }

    private var config = WineConfig()

    func initialize() {
        guard !isInitialized else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        winePrefix = documentsPath.appendingPathComponent("Wine").path
        wineBinaryPath = documentsPath.appendingPathComponent("Wine").appendingPathComponent("wine64").path

        setupWinePrefix()
        setupEnvironment()
        isInitialized = true
        print("[Wine] Initialized successfully with \(config.wineVersion)")
    }

    private func setupWinePrefix() {
        let fileManager = FileManager.default

        let wineDir = URL(fileURLWithPath: winePrefix)
        if !fileManager.fileExists(atPath: wineDir.path) {
            try? fileManager.createDirectory(at: wineDir, withIntermediateDirectories: true)
        }

        let bottlePaths = ["drive_c", "drive_c/windows", "drive_c/windows/system32",
                          "drive_c/users", "drive_c/Program Files"]
        for path in bottlePaths {
            let fullPath = wineDir.appendingPathComponent(path)
            if !fileManager.fileExists(atPath: fullPath.path) {
                try? fileManager.createDirectory(at: fullPath, withIntermediateDirectories: true)
            }
        }

        if let bundledWine = Bundle.main.path(forResource: "wine64", ofType: nil) {
            let destination = wineDir.appendingPathComponent("wine64")
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(atPath: bundledWine, toPath: destination.path)
            var attrs = try? fileManager.attributesOfItem(atPath: destination.path)
            attrs?[.posixPermissions] = 0o755
            if let attrs = attrs {
                try? fileManager.setAttributes(attrs, ofItemAtPath: destination.path)
            }
        }

        if let bundledRootfs = Bundle.main.path(forResource: "rootfs", ofType: "tzst") {
            extractRootfs(source: bundledRootfs, destination: wineDir.appendingPathComponent("rootfs").path)
        }
    }

    private func extractRootfs(source: String, destination: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-xf", source, "-C", destination]
        try? process.run()
        process.waitUntilExit()
    }

    private func setupEnvironment() {
        setenv("WINEPREFIX", winePrefix, 1)
        setenv("WINEDEBUG", config.debugChannels.joined(separator: ","), 1)
        setenv("DISPLAY", ":0", 1)
        setenv("WINEARCH", "win64", 1)
        setenv("WINEESYNC", "1", 1)
        setenv("WINEFSYNC", "1", 1)
        setenv("STAGING_SHARED_MEMORY", "1", 1)

        switch config.renderer {
        case .vulkan:
            setenv("WINE_VULKAN", "1", 1)
            setenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        case .gl, .glsl:
            setenv("WINE_GL", "1", 1)
            setenv("WINE_GL_VERSION", "3.2", 1)
        case .vkd3d:
            setenv("WINE_VKD3D", "1", 1)
        case .dxvk:
            setenv("DXVK", "1", 1)
            setenv("DXVK_HUD", "fps", 1)
        }

        if config.useCSMT {
            setenv("WINE_CSMT", "1", 1)
        }
        if config.useStrictDrawOrdering {
            setenv("WINE_STRICT_DRAW_ORDERING", "1", 1)
        }
    }

    func launchGame(executablePath: String, arguments: [String] = [], containerPath: String? = nil) -> Process? {
        guard isInitialized else {
            print("[Wine] Not initialized")
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinaryPath)
        process.arguments = [executablePath] + arguments

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefix
        if let container = containerPath {
            env["WINE_CONTAINER"] = container
        }
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8) {
                print("[Wine:stdout] \(str)")
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let str = String(data: data, encoding: .utf8) {
                print("[Wine:stderr] \(str)")
            }
        }

        do {
            try process.run()
            return process
        } catch {
            print("[Wine] Failed to launch game: \(error)")
            return nil
        }
    }

    func runWineCommand(_ command: String, arguments: [String] = []) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: wineBinaryPath)
        process.arguments = [command] + arguments

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefix
        process.environment = env

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            process.waitUntilExit()

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: outData, encoding: .utf8) ?? ""
            let errors = String(data: errData, encoding: .utf8) ?? ""

            return (process.terminationStatus, output + errors)
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    func killWine() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        process.arguments = ["-9", "wineserver"]
        try? process.run()
        process.waitUntilExit()
    }

    func updateConfig(_ updater: (inout WineConfig) -> Void) {
        updater(&config)
        setupEnvironment()
    }

    func getWinePrefixPath() -> String {
        return winePrefix
    }

    func getDriveCPath() -> String {
        return winePrefix + "/drive_c"
    }

    func installDirectX() {
        let _ = runWineCommand("wine", arguments: ["reg", "add", "HKCU\\Software\\Wine\\Direct3D", "/v", "UseGLSL", "/d", "enabled", "/f"])
        let _ = runWineCommand("wine", arguments: ["reg", "add", "HKCU\\Software\\Wine\\Direct3D", "/v", "DirectDrawRenderer", "/d", "opengl", "/f"])
        let _ = runWineCommand("wine", arguments: ["reg", "add", "HKCU\\Software\\Wine\\Direct3D", "/v", "OffscreenRenderingMode", "/d", "fbo", "/f"])
        let _ = runWineCommand("wine", arguments: ["reg", "add", "HKCU\\Software\\Wine\\Direct3D", "/v", "VideoMemorySize", "/d", "2048", "/f"])
        let _ = runWineCommand("wine", arguments: ["reg", "add", "HKCU\\Software\\Wine\\Direct3D", "/v", "MaxFrameLatency", "/d", "1", "/f"])
    }
}
