import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private var isInitialized = false
    private var box64InstallPath: String = ""
    private var ctx: OpaquePointer?

    struct Box64Config {
        var enableDynarec: Bool = true
        var dynarecBigBlock: Bool = true
        var dynarecStrongMem: Bool = true
        var dynarecSafeFlags: Bool = true
        var dynarecAltiVec: Bool = false
        var dynarecCallret: Bool = true
        var dynarecDirty: Bool = true
        var dynarecX8664: Bool = true
        var dynarecX87: Bool = true
        var dynarecFpRound: Bool = true
        var dynarecUnsafeFp: Bool = false
        var box64Debug: Bool = false
        var box64NoBanned: Bool = true
        var envVars: [String: String] = [:]
    }

    private var config = Box64Config()

    func initialize() {
        guard !isInitialized else { return }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        box64InstallPath = documentsPath.appendingPathComponent("Box64").path
        setupBox64Binary()
        setupEnvironment()

        ctx = box64_create()
        if let ctx = ctx {
            box64_init(ctx, box64InstallPath)
        }

        isInitialized = true
    }

    private func setupBox64Binary() {
        let fm = FileManager.default
        let box64Dir = URL(fileURLWithPath: box64InstallPath)
        if !fm.fileExists(atPath: box64Dir.path) {
            try? fm.createDirectory(at: box64Dir, withIntermediateDirectories: true)
        }
        if let bundledBox64 = Bundle.main.path(forResource: "box64", ofType: nil) {
            let destination = box64Dir.appendingPathComponent("box64")
            try? fm.removeItem(at: destination)
            try? fm.copyItem(atPath: bundledBox64, toPath: destination.path)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        }
    }

    private func setupEnvironment() {
        setenv("BOX64_DYNAREC", config.enableDynarec ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_BIGBLOCK", config.dynarecBigBlock ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_STRONGMEM", config.dynarecStrongMem ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_SAFEFLAGS", config.dynarecSafeFlags ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_CALLRET", config.dynarecCallret ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_DIRTY", config.dynarecDirty ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_X86_64", config.dynarecX8664 ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_X87", config.dynarecX87 ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_FPROUND", config.dynarecFpRound ? "1" : "0", 1)
        setenv("BOX64_NOBANNED", config.box64NoBanned ? "1" : "0", 1)
        setenv("BOX64_LOG", config.box64Debug ? "1" : "0", 1)

        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        setenv("HOME", docs.appendingPathComponent("Wine").path, 1)
        setenv("PATH", box64InstallPath + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)

        for (key, value) in config.envVars {
            setenv(key, value, 1)
        }
    }

    func launchWine(wine64Path: String, executablePath: String, containerPath: String, environment: [String: String]) -> Process? {
        guard isInitialized else {
            print("[Box64] Not initialized")
            return nil
        }

        let box64Binary = box64InstallPath + "/box64"
        guard FileManager.default.fileExists(atPath: box64Binary) else {
            print("[Box64] Binary not found at \(box64Binary)")
            return nil
        }

        setenv("WINEPREFIX", containerPath, 1)
        setenv("HOME", containerPath, 1)
        setenv("WINEARCH", "win64", 1)
        setenv("WINEDEBUG", "-all", 1)
        setenv("WINEESYNC", "1", 1)
        setenv("WINEFSYNC", "1", 1)
        setenv("STAGING_SHARED_MEMORY", "1", 1)
        setenv("DXVK_HUD", "fps", 1)
        setenv("DXVK_ASYNC", "1", 1)
        setenv("WINE_DLL Overrides", "dxgi,d3d11,d3d9=native,builtin", 1)

        for (key, value) in environment {
            setenv(key, value, 1)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64Binary)
        process.arguments = [wine64Path, executablePath]

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = containerPath
        env["HOME"] = containerPath
        env["WINEARCH"] = "win64"
        env["WINEDEBUG"] = "-all"
        env["WINEESYNC"] = "1"
        env["WINEFSYNC"] = "1"
        env["STAGING_SHARED_MEMORY"] = "1"
        env["DXVK_HUD"] = "fps"
        env["DXVK_ASYNC"] = "1"
        env["WINE_DLL Overrides"] = "dxgi,d3d11,d3d9=native,builtin"

        for (key, value) in environment {
            env[key] = value
        }
        process.environment = env

        let outPipe = iOSPipe()
        process.standardOutput = outPipe
        process.standardError = outPipe

        do {
            try process.run()
            print("[Box64] Launched: box64 \(wine64Path) \(executablePath)")
            return process
        } catch {
            print("[Box64] Launch failed: \(error)")
            return nil
        }
    }

    func executeX86Binary(path: String, arguments: [String], environment: [String: String]? = nil) -> Int32 {
        guard isInitialized else { return -1 }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64InstallPath + "/box64")
        process.arguments = [path] + arguments
        var env = ProcessInfo.processInfo.environment
        if let customEnv = environment {
            for (key, value) in customEnv { env[key] = value }
        }
        process.environment = env
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            print("[Box64] Failed to execute: \(error)")
            return -1
        }
    }

    func getEmulatorStatus() -> String {
        guard let ctx = ctx else { return "not initialized" }
        return String(cString: box64_get_status(ctx))
    }

    func updateConfig(_ updater: (inout Box64Config) -> Void) {
        updater(&config)
        setupEnvironment()
    }

    func getBox64Version() -> String {
        let result = executeX86Binary(path: "", arguments: ["--version"])
        return result == 0 ? "installed" : "not found"
    }

    func deinitialize() {
        if let ctx = ctx {
            box64_destroy(ctx)
            self.ctx = nil
        }
        isInitialized = false
    }
}
