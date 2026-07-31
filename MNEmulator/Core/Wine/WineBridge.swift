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
        defer { lock.unlock() }
        guard !isInitialized else {
            NSLog("[MNEmulator] WineBridge already initialized, skipping")
            return
        }
        NSLog("[MNEmulator] WineBridge initialize() start")
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        winePrefix = docs.appendingPathComponent("Wine").path
        wineBinaryPath = docs.appendingPathComponent("Wine/bin/wine64").path
        NSLog("[MNEmulator] WineBridge winePrefix=%@ wineBinaryPath=%@", winePrefix, wineBinaryPath)
        setupEnvironment()
        isInitialized = true
        NSLog("[MNEmulator] WineBridge initialize() done")
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
        lock.lock()
        let currentPrefix = winePrefix
        let currentBinaryPath = wineBinaryPath
        lock.unlock()

        let targetPrefix = containerPath ?? currentPrefix
        let wine64Path = (containerPath != nil)
            ? (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory()))
                .appendingPathComponent("Wine/bin/wine64").path
            : currentBinaryPath

        return Box64Bridge.shared.launchWine(
            wine64Path: wine64Path,
            executablePath: executablePath,
            containerPath: targetPrefix,
            environment: [:]
        )
    }

    func killWine() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let wineserverPath = docs.appendingPathComponent("Wine/bin/wineserver").path

        if fm.fileExists(atPath: wineserverPath) {
            let process = NativeProcess()
            process.executableURL = URL(fileURLWithPath: wineserverPath)
            process.arguments = ["-k"]
            try? process.run()
            DispatchQueue.global(qos: .utility).async { process.waitUntilExit() }
        }
    }

    func getWinePrefixPath() -> String { lock.lock(); defer { lock.unlock() }; return winePrefix }
    func getDriveCPath() -> String { lock.lock(); defer { lock.unlock() }; return winePrefix + "/drive_c" }
}
