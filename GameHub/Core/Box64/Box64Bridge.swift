import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private var isInitialized = false
    private var box64InstallPath: String = ""
    private var wineInstallPath: String = ""
    private var graphicsInstallPath: String = ""
    private var ctx: UnsafeMutablePointer<box64_context_t>?

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

    enum SetupError: LocalizedError {
        case box64Missing
        case wineMissing
        case copyFailed(String)

        var errorDescription: String? {
            switch self {
            case .box64Missing: return "Box64 binary not found in app bundle"
            case .wineMissing: return "Wine binaries not found in app bundle"
            case .copyFailed(let detail): return "Failed to setup binaries: \(detail)"
            }
        }
    }

    var isSetupComplete: Bool {
        let fm = FileManager.default
        let box64Exists = fm.fileExists(atPath: box64InstallPath + "/box64")
        let wineExists = fm.fileExists(atPath: wineInstallPath + "/bin/wine64")
        return box64Exists && wineExists
    }

    private func findBundledResource(_ name: String, isDirectory: Bool) -> String? {
        // Try Bundle.main.path first (works for resources registered in the bundle)
        if let path = Bundle.main.path(forResource: name, ofType: nil) {
            return path
        }
        // Try direct bundle path (works for manually injected files)
        let directPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("BundledBinaries/\(name)")
        if FileManager.default.fileExists(atPath: directPath) {
            return directPath
        }
        // Try nested BundledBinaries (for folder references)
        let nestedPath = (Bundle.main.bundlePath as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: nestedPath) {
            return nestedPath
        }
        return nil
    }

    func setupAllBundledBinaries(progressCallback: ((String) -> Void)? = nil) throws {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw SetupError.copyFailed("Cannot access Documents directory")
        }

        box64InstallPath = docs.appendingPathComponent("Box64").path
        wineInstallPath = docs.appendingPathComponent("Wine").path
        graphicsInstallPath = docs.appendingPathComponent("Graphics").path

        // Only create Graphics parent dir (subdirs created by their extract functions)
        try fm.createDirectory(at: docs.appendingPathComponent("Graphics"), withIntermediateDirectories: true)

        progressCallback?("Extracting Box64...")
        try extractBox64()

        progressCallback?("Extracting Wine...")
        try extractWine()

        progressCallback?("Extracting MoltenVK...")
        try extractMoltenVK()

        progressCallback?("Extracting DXVK...")
        try extractDXVK()
    }

    private func extractBox64() throws {
        let fm = FileManager.default
        let destination = (box64InstallPath as NSString).appendingPathComponent("box64")

        if fm.fileExists(atPath: destination) {
            print("[Box64] box64 already exists at \(destination)")
            return
        }

        guard let bundledPath = findBundledResource("box64", isDirectory: false) else {
            print("[Box64] box64 NOT found in bundle. Checked: \(Bundle.main.bundlePath)/BundledBinaries/box64")
            throw SetupError.box64Missing
        }
        print("[Box64] Found bundled box64 at: \(bundledPath)")
        try fm.copyItem(atPath: bundledPath, toPath: destination)
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination)
        print("[Box64] Extracted box64 to \(destination)")
    }

    private func extractWine() throws {
        let fm = FileManager.default
        let wine64Dest = (wineInstallPath as NSString).appendingPathComponent("bin/wine64")

        if fm.fileExists(atPath: wine64Dest) {
            print("[Box64] Wine already extracted at \(wine64Dest)")
            return
        }

        guard let bundledWineDir = findBundledResource("Wine", isDirectory: true) else {
            print("[Box64] Wine NOT found in bundle. Checked paths:")
            print("  1. \(Bundle.main.path(forResource: "Wine", ofType: nil) ?? "nil")")
            print("  2. \(Bundle.main.bundlePath)/BundledBinaries/Wine")
            print("  3. \(Bundle.main.bundlePath)/Wine")
            throw SetupError.wineMissing
        }
        print("[Box64] Found bundled Wine at: \(bundledWineDir)")

        if fm.fileExists(atPath: wine64Dest) { return }

        // Remove pre-created empty Wine directory so copyItem won't fail (destination already exists)
        if fm.fileExists(atPath: wineInstallPath) {
            print("[Box64] Removing pre-existing empty Wine dir at \(wineInstallPath)")
            try? fm.removeItem(atPath: wineInstallPath)
        }

        try fm.copyItem(atPath: bundledWineDir, toPath: wineInstallPath)

        let binaries = ["bin/wine", "bin/wine64", "bin/wineserver", "bin/wineboot",
                        "bin/winecfg", "bin/winepath"]
        for bin in binaries {
            let binPath = (wineInstallPath as NSString).appendingPathComponent(bin)
            if fm.fileExists(atPath: binPath) {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binPath)
            }
        }

        print("[Box64] Extracted Wine to \(wineInstallPath)")
    }

    private func extractMoltenVK() throws {
        let fm = FileManager.default
        let mvkDir = (graphicsInstallPath as NSString).appendingPathComponent("MoltenVK")
        let mvkDest = mvkDir + "/libMoltenVK.dylib"

        if fm.fileExists(atPath: mvkDest) {
            print("[Box64] MoltenVK already extracted")
            return
        }

        guard let bundledMVK = findBundledResource("MoltenVK", isDirectory: true) else {
            print("[Box64] MoltenVK not found in bundle, skipping")
            return
        }
        print("[Box64] Found bundled MoltenVK at: \(bundledMVK)")

        if fm.fileExists(atPath: mvkDir) {
            try? fm.removeItem(atPath: mvkDir)
        }
        try fm.copyItem(atPath: bundledMVK, toPath: mvkDir)
        print("[Box64] Extracted MoltenVK")
    }

    private func extractDXVK() throws {
        let fm = FileManager.default
        let dxvkDir = (graphicsInstallPath as NSString).appendingPathComponent("DXVK")

        if let contents = try? fm.contentsOfDirectory(atPath: dxvkDir), !contents.isEmpty {
            print("[Box64] DXVK already extracted")
            return
        }

        guard let bundledDXVK = findBundledResource("DXVK", isDirectory: true) else {
            print("[Box64] DXVK not found in bundle, skipping")
            return
        }
        print("[Box64] Found bundled DXVK at: \(bundledDXVK)")

        if fm.fileExists(atPath: dxvkDir) {
            try? fm.removeItem(atPath: dxvkDir)
        }
        try fm.copyItem(atPath: bundledDXVK, toPath: dxvkDir)
        print("[Box64] Extracted DXVK")
    }

    func initialize() {
        guard !isInitialized else { return }
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        box64InstallPath = documentsPath.appendingPathComponent("Box64").path
        wineInstallPath = documentsPath.appendingPathComponent("Wine").path
        graphicsInstallPath = documentsPath.appendingPathComponent("Graphics").path
        setupEnvironment()

        ctx = box64_create()
        if let ctx = ctx {
            box64_init(ctx, box64InstallPath)
        }

        isInitialized = true
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
        setenv("PATH", box64InstallPath + ":" + wineInstallPath + "/bin:" + (ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"), 1)

        for (key, value) in config.envVars {
            setenv(key, value, 1)
        }
    }

    struct LaunchResult {
        var process: Process?
        var error: String?
        var box64Output: String?
    }

    func launchWine(wine64Path: String, executablePath: String, containerPath: String, environment: [String: String]) -> LaunchResult {
        var result = LaunchResult()

        guard isInitialized else {
            result.error = "Box64 not initialized (ctx is nil)"
            return result
        }

        let box64Binary = box64InstallPath + "/box64"
        guard FileManager.default.fileExists(atPath: box64Binary) else {
            result.error = "Box64 binary not found at: \(box64Binary)"
            return result
        }

        guard FileManager.default.fileExists(atPath: wine64Path) else {
            result.error = "Wine binary not found at: \(wine64Path)"
            return result
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: box64Binary)
        if let perm = attrs?[.posixPermissions] as? Int {
            if perm & 0o111 == 0 {
                try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box64Binary)
            }
        }

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
        env["DXVK_LOG_LEVEL"] = "none"
        env["WINE_DLL Overrides"] = "dxgi,d3d11,d3d9=native,builtin"
        env["DISPLAY"] = ":0"

        for (key, value) in environment {
            env[key] = value
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64Binary)
        process.arguments = [wine64Path, executablePath]
        process.environment = env

        let outPipe = iOSPipe()
        let errPipe = iOSPipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
            print("[Box64] Launched: box64 \(wine64Path) \(executablePath)")

            DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
                let out = outPipe?.readOutput(timeout: 1) ?? ""
                let err = errPipe?.readOutput(timeout: 1) ?? ""
                if !out.isEmpty || !err.isEmpty {
                    print("[Box64] stdout: \(out)")
                    print("[Box64] stderr: \(err)")
                }
            }

            result.process = process
            return result
        } catch {
            let errOut = errPipe?.readOutput(timeout: 0.5) ?? ""
            result.error = "posix_spawn failed: \(error.localizedDescription)"
            if !errOut.isEmpty {
                result.error! += "\n\nOutput: \(errOut)"
            }
            result.box64Output = errOut
            print("[Box64] Launch failed: \(error)")
            return result
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
