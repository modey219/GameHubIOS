import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private let lock = NSLock()
    private var isInitialized = false
    private var box64InstallPath: String = ""
    private var wineInstallPath: String = ""
    private var graphicsInstallPath: String = ""
    private var ctx: UnsafeMutablePointer<box64_context_t>?
    private var launchThread: pthread_t?
    private var _isRunning = false

    private static let logQueue = DispatchQueue(label: "com.box64.swiftlog")
    private static var logFD: Int32 = -1
    private static let logDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static func log(_ msg: String) {
        let ts = logDateFormatter.string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        logQueue.sync {
            if logFD < 0 {
                let home = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    .map { $0.path } ?? "/tmp"
                let path = "\(home)/swift_box64.log"
                logFD = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
            }
            if logFD >= 0 {
                line.withCString { ptr in
                    _ = write(logFD, ptr, strlen(ptr))
                }
            }
        }
    }

    struct LaunchResult {
        var process: NativeProcess?
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

    var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isRunning
    }

    private func findBundledResource(_ name: String, isDirectory: Bool) -> String? {
        if let path = Bundle.main.path(forResource: name, ofType: nil) { return path }
        let directPath = (Bundle.main.bundlePath as NSString).appendingPathComponent("BundledBinaries/\(name)")
        if FileManager.default.fileExists(atPath: directPath) { return directPath }
        let nestedPath = (Bundle.main.bundlePath as NSString).appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: nestedPath) { return nestedPath }
        return nil
    }

    private static func memoryUsageMB() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? UInt64(info.resident_size) / (1024 * 1024) : 0
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

        Self.log("setupAllBundledBinaries: memory before extraction = \(Self.memoryUsageMB())MB")

        progressCallback?("Extracting Box64...")
        try autoreleasepool {
            try extractBox64()
        }
        Self.log("memory after Box64 extraction = \(Self.memoryUsageMB())MB")

        progressCallback?("Extracting Wine...")
        try autoreleasepool {
            try extractWine()
        }
        Self.log("memory after Wine extraction = \(Self.memoryUsageMB())MB")

        progressCallback?("Extracting MoltenVK...")
        autoreleasepool {
            do { try extractMoltenVK() } catch { Self.log("extractMoltenVK skipped: \(error)") }
        }
        Self.log("memory after MoltenVK extraction = \(Self.memoryUsageMB())MB")

        progressCallback?("Extracting DXVK...")
        autoreleasepool {
            do { try extractDXVK() } catch { Self.log("extractDXVK skipped: \(error)") }
        }
        Self.log("setupAllBundledBinaries: memory after all = \(Self.memoryUsageMB())MB")
    }

    func initialize() {
        lock.lock()
        guard !isInitialized else { lock.unlock(); return }
        Self.log("initialize() called")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
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
            isInitialized = true
        } else {
            Self.log("box64_create returned NULL!")
        }
        lock.unlock()

        Self.log("initialize() complete, isInitialized=\(isInitialized)")
    }

    private func setupEnvironment() {
        safeSetenv("BOX64_DYNAREC", "0", 1)
        safeSetenv("BOX64_NOBANNED", "1", 1)
        safeSetenv("BOX64_LOG", "1", 1)
        safeSetenv("BOX64_SHOWSEGV", "1", 1)
        safeSetenv("BOX64_SHOWEXIT", "1", 1)
        safeSetenv("BOX64_NOSSE", "1", 1)
        safeSetenv("HOME", (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory).appendingPathComponent("Wine").path, 1)
        safeSetenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        safeSetenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1)
        safeSetenv("DXVK_LOG_LEVEL", "none", 1)
        safeSetenv("DXVK_HUD", "fps", 1)
        safeSetenv("VKD3D_CONFIG", "dxr", 1)
    }

    func launchWine(wine64Path: String, executablePath: String, containerPath: String, environment: [String: String]) -> LaunchResult {
        Self.log("launchWine() called: exe=\(executablePath)")
        Self.log("wine64Path=\(wine64Path) container=\(containerPath)")
        var result = LaunchResult()

        lock.lock()
        let initialized = isInitialized
        let ctxPtr = ctx
        lock.unlock()

        guard initialized, let ctx = ctxPtr else {
            Self.log("ERROR: Box64 not initialized")
            result.error = "Box64 not initialized. Please restart the app."
            return result
        }

        safeSetenv("WINEPREFIX", containerPath, 1)
        safeSetenv("WINEARCH", "win64", 1)
        safeSetenv("WINEDEBUG", "-all", 1)
        safeSetenv("WINEESYNC", "1", 1)
        safeSetenv("WINEFSYNC", "1", 1)
        safeSetenv("STAGING_SHARED_MEMORY", "1", 1)
        safeSetenv("DXVK_HUD", "fps", 1)
        safeSetenv("DXVK_ASYNC", "1", 1)
        safeSetenv("DXVK_LOG_LEVEL", "none", 1)
        safeSetenv("DISPLAY", ":0", 1)

        for (key, value) in environment {
            safeSetenv(key, value, 1)
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
            result.error = "Failed to launch Box64+Wine (error \(rc)):\n\(errStr)\n\n" +
                "Binary: \(wine64Path)\n" +
                "Exe: \(executablePath)\n\n" +
                "iOS cannot execute unsigned binaries from the Documents folder.\n" +
                "Possible fixes:\n" +
                "1. Jailbreak your device (JIT enabled)\n" +
                "2. Use TrollStore for unsigned execution\n" +
                "3. Enable JIT via StikDebug first"
            return result
        }

        Self.log("launchWine SUCCESS")
        lock.lock()
        _isRunning = true
        lock.unlock()
        result.wineLaunched = true
        result.box64Output = "Wine launched via box64 bridge (thread-based)"

        return result
    }

    func stopWine() {
        guard let ctx = ctx else { return }
        box64_stop(ctx)
        lock.lock()
        _isRunning = false
        lock.unlock()
    }

    func getEmulatorStatus() -> String {
        guard let ctx = ctx else { return "not initialized" }
        guard let cStr = box64_get_status(ctx) else { return "unknown" }
        return String(cString: cStr)
    }

    func getRunnerLog() -> String {
        let maxLinesPerFile = 500
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        var parts: [String] = []

        if let savedLog = UserDefaults.standard.string(forKey: "last_launch_log"), !savedLog.isEmpty {
            let lines = savedLog.components(separatedBy: "\n")
            let trimmed = lines.count > maxLinesPerFile ? Array(lines.suffix(maxLinesPerFile)) : lines
            parts.append("=== Launch Log (UserDefaults) ===\n\(trimmed.joined(separator: "\n"))")
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
                let lines = content.components(separatedBy: "\n")
                let trimmed = lines.count > maxLinesPerFile ? Array(lines.suffix(maxLinesPerFile)) : lines
                parts.append("=== \(label) (\(trimmed.count)/\(lines.count) lines) ===\n\(trimmed.joined(separator: "\n"))")
            }
        }

        if let cPath = box64_runner_get_log_path() {
            let path = String(cString: cPath)
            if !path.isEmpty, !candidates.contains(path),
               let data = FileManager.default.contents(atPath: path),
               let content = String(data: data, encoding: .utf8), !content.isEmpty {
                let lines = content.components(separatedBy: "\n")
                let trimmed = lines.count > maxLinesPerFile ? Array(lines.suffix(maxLinesPerFile)) : lines
                parts.append("=== runner (\(trimmed.count)/\(lines.count) lines) ===\n\(trimmed.joined(separator: "\n"))")
            }
        }

        return parts.isEmpty ? "No logs found. Run a game first." : parts.joined(separator: "\n\n")
    }

    func deinitialize() {
        lock.lock()
        if let ctx = ctx {
            box64_destroy(ctx)
            self.ctx = nil
        }
        isInitialized = false
        _isRunning = false
        lock.unlock()
        if logFD >= 0 { close(logFD); logFD = -1 }
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
        let process = NativeProcess()
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
