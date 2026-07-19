import Foundation

class WineBridge {
    static let shared = WineBridge()
    private var isInitialized = false
    private var winePrefix: String = ""
    private var wineBinaryPath: String = ""

    enum Renderer: String, CaseIterable {
        case vulkan = "vulkan"
        case gl = "opengl"
        case dxvk = "dxvk"
        var displayName: String {
            switch self {
            case .vulkan: return "Vulkan (MoltenVK)"
            case .gl: return "OpenGL ES"
            case .dxvk: return "DXVK (DX11)"
            }
        }
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: wineBinaryPath)
    }

    func initialize() {
        guard !isInitialized else { return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        winePrefix = docs.appendingPathComponent("Wine").path
        wineBinaryPath = docs.appendingPathComponent("Wine/bin/wine64").path
        setupWinePrefix()
        setupEnvironment()
        isInitialized = true
    }

    private func setupWinePrefix() {
        let fm = FileManager.default
        let wineDir = URL(fileURLWithPath: winePrefix)
        let dirs = ["drive_c", "drive_c/windows", "drive_c/windows/system32",
                     "drive_c/users", "drive_c/Program Files", "drive_c/games", "input", "logs"]
        for path in dirs {
            try? fm.createDirectory(at: wineDir.appendingPathComponent(path), withIntermediateDirectories: true)
        }
    }

    private func setupEnvironment() {
        setenv("WINEPREFIX", winePrefix, 1)
        setenv("WINEDEBUG", "-all", 1)
        setenv("DISPLAY", ":0", 1)
        setenv("WINEARCH", "win64", 1)
        setenv("WINEESYNC", "1", 1)
        setenv("WINEFSYNC", "1", 1)
        setenv("STAGING_SHARED_MEMORY", "1", 1)
    }

    func launchGame(executablePath: String, arguments: [String] = [], containerPath: String? = nil) -> Box64Bridge.LaunchResult {
        let targetPrefix = containerPath ?? winePrefix
        let wine64Path = (containerPath != nil)
            ? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("Wine/bin/wine64").path
            : wineBinaryPath

        return Box64Bridge.shared.launchWine(
            wine64Path: wine64Path,
            executablePath: executablePath,
            containerPath: targetPrefix,
            environment: [:]
        )
    }

    func killWine() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "killall -9 wineserver 2>/dev/null; killall -9 wine64 2>/dev/null; killall -9 box64 2>/dev/null"]
        try? process.run()
        DispatchQueue.global(qos: .utility).async { process.waitUntilExit() }
    }

    func getWinePrefixPath() -> String { winePrefix }
    func getDriveCPath() -> String { winePrefix + "/drive_c" }
}
