import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private var isInitialized = false
    private var box64InstallPath: String = ""
    private var wineInstallPath: String = ""
    private var graphicsInstallPath: String = ""
    private var ctx: UnsafeMutablePointer<box64_context_t>?
    private var launchThread: pthread_t?
    private var _isRunning = false

    private static let logQueue = DispatchQueue(label: "com.box64.swiftlog")
    private static var logFD: Int32 = -1

    static func log(_ msg: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        logQueue.sync {
            if logFD < 0 {
                let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path
                let path = "\(home)/swift_box64.log"
                logFD = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            }
            if logFD >= 0 {
                line.withCString { ptr in
                    _ = write(logFD, ptr, strlen(ptr))
                    fsync(logFD)
                }
            }
        }
    }

    struct LaunchResult {
        var process: Process?
        var error: String?
        var box64Output: String?
        var wineLaunched: Bool = false
    }

    var isSetupComplete: Bool {
        let fm = FileManager.default
        let box64Exists = fm.fileExists(atPath: box64InstallPath + "/box64")
        let wineExists = fm.fileExists(atPath: wineInstallPath + "/bin/wine64")
        return box64Exists && wineExists
    }

    var isRunning: Bool { _isRunning }

    private func findBundledResource(_ name: String, isDirectory: Bool) -> String? {
        if let path = Bundle.main.path(forResource: name, ofType: nil) { return path }
        let directPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("BundledBinaries/\(name)")
        if FileManager.default.fileExists(atPath: directPath) { return directPath }
        let nestedPath = (Bundle.main.bundlePath as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: nestedPath) { return nestedPath }
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

        try fm.createDirectory(at: docs.appendingPathComponent("Graphics"), withIntermediateDirectories: true)

        progressCallback?("Extracting Box64...")
        try extractBox64()
        progressCallback?("Extracting Wine...")
        try extractWine()
        progressCallback?("Extracting MoltenVK...")
        try extractMoltenVK()
        progressCallback?("Extracting DXVK...")
        try extractDXVK()

        progressCallback?("Copying binaries to temp (for execution)...")
        copyBinariesToTemp()
    }

    private func copyBinariesToTemp() {
        let fm = FileManager.default
        let tmp = NSTemporaryDirectory()

        let box64Src = box64InstallPath + "/box64"
        let box64Tmp = tmp + "box64"
        if fm.fileExists(atPath: box64Src) && !fm.fileExists(atPath: box64Tmp) {
            try? fm.copyItem(atPath: box64Src, toPath: box64Tmp)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: box64Tmp)
            print("[Box64] Copied box64 to \(box64Tmp)")
        }

        let wine64Src = wineInstallPath + "/bin/wine64"
        let wine64Tmp = tmp + "wine64"
        if fm.fileExists(atPath: wine64Src) && !fm.fileExists(atPath: wine64Tmp) {
            try? fm.copyItem(atPath: wine64Src, toPath: wine64Tmp)
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wine64Tmp)
            print("[Box64] Copied wine64 to \(wine64Tmp)")
        }
    }

    func initialize() {
        guard !isInitialized else { return }
        Self.log("initialize() called")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        box64InstallPath = documentsPath.appendingPathComponent("Box64").path
        wineInstallPath = documentsPath.appendingPathComponent("Wine").path
        graphicsInstallPath = documentsPath.appendingPathComponent("Graphics").path
        Self.log("box64InstallPath = \(box64InstallPath)")
        Self.log("wineInstallPath = \(wineInstallPath)")
        setupEnvironment()

        Self.log("calling box64_create()...")
        ctx = box64_create()
        if let ctx = ctx {
            Self.log("box64_create OK, calling box64_init...")
            box64_init(ctx, box64InstallPath)
            Self.log("box64_init done")
        } else {
            Self.log("box64_create returned NULL!")
        }

        isInitialized = true
        Self.log("initialize() complete")
    }

    private func setupEnvironment() {
        setenv("BOX64_DYNAREC", "0", 1)
        setenv("BOX64_NOBANNED", "1", 1)
        setenv("BOX64_LOG", "1", 1)
        setenv("BOX64_SHOWSEGV", "1", 1)
        setenv("BOX64_SHOWEXIT", "1", 1)
        setenv("BOX64_NOSSE", "1", 1)
        setenv("HOME", FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Wine").path, 1)
    }

    func launchWine(wine64Path: String, executablePath: String, containerPath: String, environment: [String: String]) -> LaunchResult {
        Self.log("launchWine() called: exe=\(executablePath)")
        Self.log("wine64Path=\(wine64Path) container=\(containerPath)")
        var result = LaunchResult()

        guard isInitialized, let ctx = ctx else {
            Self.log("ERROR: Box64 not initialized")
            result.error = "Box64 not initialized. Please restart the app."
            return result
        }

        setenv("WINEPREFIX", containerPath, 1)
        setenv("WINEARCH", "win64", 1)
        setenv("WINEDEBUG", "-all", 1)
        setenv("WINEESYNC", "1", 1)
        setenv("WINEFSYNC", "1", 1)
        setenv("STAGING_SHARED_MEMORY", "1", 1)
        setenv("DXVK_HUD", "fps", 1)
        setenv("DXVK_ASYNC", "1", 1)
        setenv("DXVK_LOG_LEVEL", "none", 1)
        setenv("DISPLAY", ":0", 1)

        for (key, value) in environment {
            setenv(key, value, 1)
        }

        Self.log("calling box64_set_wine_path/set_prefix/set_game...")
        box64_set_wine_path(ctx, wine64Path)
        box64_set_prefix(ctx, containerPath)
        box64_set_game(ctx, executablePath)
        Self.log("calling box64_launch_wine()...")
        let rc = box64_launch_wine(ctx, executablePath, nil)
        Self.log("box64_launch_wine returned \(rc)")
        if rc != 0 {
            let cError = box64_get_wine_error()
            let errStr = cError != nil ? String(cString: cError!) : ""
            Self.log("ERROR: box64_launch_wine failed: \(errStr)")
            result.error = "Failed to launch Box64+Wine (error \(rc)):\n\(errStr)\n\n"
            result.error! += "Binary: \(wine64Path)\n"
            result.error! += "Exe: \(executablePath)\n\n"
            result.error! += "iOS cannot execute unsigned binaries from the Documents folder.\n"
            result.error! += "Possible fixes:\n"
            result.error! += "1. Jailbreak your device (JIT enabled)\n"
            result.error! += "2. Use TrollStore for unsigned execution\n"
            result.error! += "3. Enable JIT via StikDebug first"
            return result
        }

        Self.log("launchWine SUCCESS")
        _isRunning = true
        result.wineLaunched = true
        result.box64Output = "Wine launched via box64 bridge (thread-based)"

        return result
    }

    func stopWine() {
        guard let ctx = ctx else { return }
        box64_stop(ctx)
        _isRunning = false
    }

    func getEmulatorStatus() -> String {
        guard let ctx = ctx else { return "not initialized" }
        return String(cString: box64_get_status(ctx))
    }

    func getRunnerLog() -> String {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var parts: [String] = []

        if let savedLog = UserDefaults.standard.string(forKey: "last_launch_log"), !savedLog.isEmpty {
            parts.append("=== Launch Log (UserDefaults) ===\n\(savedLog)")
        }

        let candidates = [
            docs.appendingPathComponent("launch.log").path,
            docs.appendingPathComponent("box64_runner.log").path,
            docs.appendingPathComponent("bridge.log").path,
            docs.appendingPathComponent("swift_box64.log").path,
        ]

        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let content = String(data: data, encoding: .utf8), !content.isEmpty {
                let label = (path as NSString).lastPathComponent
                parts.append("=== \(label) ===\n\(content)")
            }
        }

        if let cPath = box64_runner_get_log_path() {
            let path = String(cString: cPath)
            if !path.isEmpty, !candidates.contains(path),
               let data = FileManager.default.contents(atPath: path),
               let content = String(data: data, encoding: .utf8), !content.isEmpty {
                parts.append("=== runner ===\n\(content)")
            }
        }

        return parts.isEmpty ? "No logs found. Run a game first." : parts.joined(separator: "\n\n")
    }

    func deinitialize() {
        if let ctx = ctx {
            box64_destroy(ctx)
            self.ctx = nil
        }
        isInitialized = false
    }

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

    private func shellCopy(src: String, dst: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-R", src, dst]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw SetupError.copyFailed("cp -R failed with status \(process.terminationStatus)")
        }
    }

    private func streamCopy(src: String, dst: String, fm: FileManager) {
        let bufSize = 64 * 1024
        guard let inStream = InputStream(fileAtPath: src),
              let outStream = OutputStream(toFileAtPath: dst, append: false) else { return }
        inStream.open()
        outStream.open()
        let buf = UnsafeMutablePointer<UInt8>.allocate(capacity: bufSize)
        defer { buf.deallocate() }
        while inStream.hasBytesAvailable {
            let read = inStream.read(buf, maxLength: bufSize)
            if read <= 0 { break }
            outStream.write(buf, maxLength: read)
        }
        inStream.close()
        outStream.close()
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
    }

    private func extractBox64() throws {
        let fm = FileManager.default
        let destination = (box64InstallPath as NSString).appendingPathComponent("box64")
        if fm.fileExists(atPath: destination) { return }

        guard let bundledPath = findBundledResource("box64", isDirectory: false) else {
            throw SetupError.box64Missing
        }
        streamCopy(src: bundledPath, dst: destination, fm: fm)
    }

    private func copyDirRecursive(src: String, dst: String, fm: FileManager) throws {
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: src)
        for item in contents {
            autoreleasepool {
                let srcPath = (src as NSString).appendingPathComponent(item)
                let dstPath = (dst as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try? copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    streamCopy(src: srcPath, dst: dstPath, fm: fm)
                }
            }
        }
    }

    private func extractWine() throws {
        let fm = FileManager.default
        let wine64Dest = (wineInstallPath as NSString).appendingPathComponent("bin/wine64")
        if fm.fileExists(atPath: wine64Dest) { return }

        guard let bundledWineDir = findBundledResource("Wine", isDirectory: true) else {
            throw SetupError.wineMissing
        }
        if fm.fileExists(atPath: wineInstallPath) {
            try? fm.removeItem(atPath: wineInstallPath)
        }

        try fm.createDirectory(atPath: wineInstallPath, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: bundledWineDir)
        for item in contents {
            autoreleasepool {
                let srcPath = (bundledWineDir as NSString).appendingPathComponent(item)
                let dstPath = (wineInstallPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try? copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    streamCopy(src: srcPath, dst: dstPath, fm: fm)
                }
            }
        }

        let binaries = ["bin/wine", "bin/wine64", "bin/wineserver", "bin/wineboot"]
        for bin in binaries {
            let binPath = (wineInstallPath as NSString).appendingPathComponent(bin)
            if fm.fileExists(atPath: binPath) {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binPath)
            }
        }
    }

    private func extractMoltenVK() throws {
        let fm = FileManager.default
        let mvkDir = (graphicsInstallPath as NSString).appendingPathComponent("MoltenVK")
        let mvkDest = mvkDir + "/libMoltenVK.dylib"
        if fm.fileExists(atPath: mvkDest) { return }

        guard let bundledMVK = findBundledResource("MoltenVK", isDirectory: true) else { return }
        if fm.fileExists(atPath: mvkDir) { try? fm.removeItem(atPath: mvkDir) }
        try fm.createDirectory(atPath: mvkDir, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: bundledMVK)
        for item in contents {
            autoreleasepool {
                let srcPath = (bundledMVK as NSString).appendingPathComponent(item)
                let dstPath = (mvkDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try? copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    streamCopy(src: srcPath, dst: dstPath, fm: fm)
                }
            }
        }
    }

    private func extractDXVK() throws {
        let fm = FileManager.default
        let dxvkDir = (graphicsInstallPath as NSString).appendingPathComponent("DXVK")
        if let contents = try? fm.contentsOfDirectory(atPath: dxvkDir), !contents.isEmpty { return }

        guard let bundledDXVK = findBundledResource("DXVK", isDirectory: true) else { return }
        if fm.fileExists(atPath: dxvkDir) { try? fm.removeItem(atPath: dxvkDir) }
        try fm.createDirectory(atPath: dxvkDir, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: bundledDXVK)
        for item in contents {
            autoreleasepool {
                let srcPath = (bundledDXVK as NSString).appendingPathComponent(item)
                let dstPath = (dxvkDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try? copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    streamCopy(src: srcPath, dst: dstPath, fm: fm)
                }
            }
        }
    }
}
