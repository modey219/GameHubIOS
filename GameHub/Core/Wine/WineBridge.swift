import Foundation

class WineBridge {
    static let shared = WineBridge()
    private let lock = NSLock()
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
        lock.lock(); defer { lock.unlock() }
        return FileManager.default.fileExists(atPath: wineBinaryPath)
    }

    func initialize() {
        lock.lock()
        guard !isInitialized else { lock.unlock(); return }
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        winePrefix = docs.appendingPathComponent("Wine").path
        wineBinaryPath = docs.appendingPathComponent("Wine/bin/wine64").path
        setupEnvironment()
        isInitialized = true
        lock.unlock()
    }

    private func setupEnvironment() {
        safeSetenv("WINEPREFIX", winePrefix, 1)
        safeSetenv("WINEDEBUG", "-all", 1)
        safeSetenv("DISPLAY", ":0", 1)
        safeSetenv("WINEARCH", "win64", 1)
        safeSetenv("WINEESYNC", "1", 1)
        safeSetenv("WINEFSYNC", "1", 1)
        safeSetenv("STAGING_SHARED_MEMORY", "1", 1)
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
        let process = NativeProcess()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", "killall -9 wineserver 2>/dev/null; killall -9 wine64 2>/dev/null; killall -9 box64 2>/dev/null"]
        try? process.run()
        DispatchQueue.global(qos: .utility).async { process.waitUntilExit() }
    }

    func getWinePrefixPath() -> String { winePrefix }
    func getDriveCPath() -> String { winePrefix + "/drive_c" }
}
