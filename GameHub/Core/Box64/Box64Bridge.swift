import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private let lock = NSLock()
    private var isInitialized = false
    private var box64InstallPath: String = ""
    private var wineInstallPath: String = ""
    private var graphicsInstallPath: String = ""
    private var ctx: UnsafeMutablePointer<box64_context_t>?
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
        lock.lock()
        let box64Path = box64InstallPath
        let winePath = wineInstallPath
        lock.unlock()
        let fm = FileManager.default
        let box64Exists = fm.fileExists(atPath: box64Path + "/box64")
        let wineExists = fm.fileExists(atPath: winePath + "/bin/wine64")
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

        progressCallback?("Extracting Box64...")
        NSLog("[MNEmulator] extractBox64 start")
        try autoreleasepool {
            try extractBox64()
        }
        NSLog("[MNEmulator] extractBox64 done")

        progressCallback?("Extracting Wine...")
        NSLog("[MNEmulator] extractWine start")
        try autoreleasepool {
            try extractWine()
        }
        NSLog("[MNEmulator] extractWine done")

        progressCallback?("Extracting MoltenVK...")
        NSLog("[MNEmulator] extractMoltenVK start")
        autoreleasepool {
            do { try extractMoltenVK() } catch { NSLog("[MNEmulator] extractMoltenVK skipped: \(error)") }
        }
        NSLog("[MNEmulator] extractMoltenVK done")

        progressCallback?("Extracting DXVK...")
        NSLog("[MNEmulator] extractDXVK start")
        autoreleasepool {
            let memMB = Self.memoryUsageMB()
            NSLog("[MNEmulator] before DXVK: memory = \(memMB)MB")
            if memMB > 350 {
                NSLog("[MNEmulator] skipping DXVK — memory too high (\(memMB)MB)")
                return
            }
            do { try extractDXVK() } catch { NSLog("[MNEmulator] extractDXVK skipped: \(error)") }
        }
        NSLog("[MNEmulator] extractDXVK done — all extraction complete")
    }

    func initialize() {
        lock.lock()
        if isInitialized { lock.unlock(); return }

        Self.log("initialize() called, memory = \(Self.memoryUsageMB())MB")
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        box64InstallPath = documentsPath.appendingPathComponent("Box64").path
        wineInstallPath = documentsPath.appendingPathComponent("Wine").path
        graphicsInstallPath = documentsPath.appendingPathComponent("Graphics").path
        Self.log("box64InstallPath = \(box64InstallPath)")
        Self.log("wineInstallPath = \(wineInstallPath)")
        setupEnvironment()

        Self.log("calling box64_create(), memory = \(Self.memoryUsageMB())MB...")
        var localCtx: UnsafeMutablePointer<box64_context_t>?
        autoreleasepool {
            localCtx = box64_create()
        }
        Self.log("box64_create returned \(localCtx != nil ? "OK" : "NULL"), memory = \(Self.memoryUsageMB())MB")

        if let localCtx = localCtx {
            Self.log("calling box64_init...")
            let initResult = box64_init(localCtx, box64InstallPath)
            Self.log("box64_init returned \(initResult)")
            if initResult == 0 {
                ctx = localCtx
                isInitialized = true
            } else {
                Self.log("box64_init FAILED — destroying context")
                box64_destroy(localCtx)
            }
        } else {
            Self.log("box64_create returned NULL! Cannot initialize.")
        }

        lock.unlock()
        Self.log("initialize() complete, isInitialized=\(isInitialized), memory = \(Self.memoryUsageMB())MB")
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
        guard isInitialized, let ctx = ctx else {
            lock.unlock()
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
        Self.log("calling box64_launch_wine(), memory = \(Self.memoryUsageMB())MB...")
        let rc: Int32 = autoreleasepool { box64_launch_wine(ctx, executablePath, nil) }
        Self.log("box64_launch_wine returned \(rc), memory = \(Self.memoryUsageMB())MB")
        if rc != 0 {
            let cError = box64_get_wine_error()
            let errStr = cError.map { String(cString: $0) } ?? ""
            Self.log("ERROR: box64_launch_wine failed: \(errStr)")
            lock.unlock()
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
        _isRunning = true
        lock.unlock()
        result.wineLaunched = true
        result.box64Output = "Wine launched via box64 bridge (thread-based)"

        return result
    }

    func stopWine() {
        lock.lock()
        guard let ctx = ctx else { lock.unlock(); return }
        box64_stop(ctx)
        _isRunning = false
        lock.unlock()
    }

    func getEmulatorStatus() -> String {
        lock.lock()
        guard let ctx = ctx else { lock.unlock(); return "not initialized" }
        guard let cStr = box64_get_status(ctx) else { lock.unlock(); return "unknown" }
        let status = String(cString: cStr)
        lock.unlock()
        return status
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
        Self.logQueue.sync {
            if Self.logFD >= 0 { close(Self.logFD); Self.logFD = -1 }
        }
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

    @discardableResult
    private func streamCopy(src: String, dst: String, fm: FileManager) -> Bool {
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src, isDirectory: &isDir), !isDir.boolValue else {
            Self.log("streamCopy: source missing or is directory: \(src)")
            return false
        }
        guard let attrs = try? fm.attributesOfItem(atPath: src),
              let size = attrs[.size] as? NSNumber, size.intValue > 0 else {
            Self.log("streamCopy: source has 0 size: \(src)")
            return false
        }
        if (try? fm.copyItem(atPath: src, toPath: dst)) != nil {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
            return true
        }
        Self.log("streamCopy: copyItem failed for \(src), falling back to stream copy")
        let bufSize = 64 * 1024
        guard let inStream = InputStream(fileAtPath: src),
              let outStream = OutputStream(toFileAtPath: dst, append: false) else {
            Self.log("streamCopy: failed to open streams for \(src)")
            return false
        }
        inStream.open()
        outStream.open()
        let buf = malloc(bufSize)
        defer { free(buf) }
        guard let bufPtr = buf?.bindMemory(to: UInt8.self, capacity: bufSize) else {
            inStream.close(); outStream.close()
            try? fm.removeItem(atPath: dst)
            return false
        }
        var totalWritten = 0
        while inStream.hasBytesAvailable {
            let bytesRead = inStream.read(bufPtr, maxLength: bufSize)
            if bytesRead <= 0 { break }
            let written = outStream.write(bufPtr, maxLength: bytesRead)
            if written > 0 { totalWritten += written }
        }
        inStream.close()
        outStream.close()
        guard totalWritten > 0 else {
            try? fm.removeItem(atPath: dst)
            Self.log("streamCopy: wrote 0 bytes to \(dst)")
            return false
        }
        try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dst)
        return true
    }

    private func isNonEmptyFile(_ path: String) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? NSNumber else { return false }
        return size.intValue > 0
    }

    private func extractBox64() throws {
        let fm = FileManager.default
        try fm.createDirectory(atPath: box64InstallPath, withIntermediateDirectories: true)
        let destination = (box64InstallPath as NSString).appendingPathComponent("box64")
        if isNonEmptyFile(destination) { return }
        if fm.fileExists(atPath: destination) {
            try? fm.removeItem(atPath: destination)
            Self.log("extractBox64: removed stale 0-byte file")
        }

        guard let bundledPath = findBundledResource("box64", isDirectory: false) else {
            throw SetupError.box64Missing
        }
        Self.log("extractBox64: source=\(bundledPath) dest=\(destination)")
        let srcExists = fm.fileExists(atPath: bundledPath)
        let srcAttrs = try? fm.attributesOfItem(atPath: bundledPath)
        let srcSize = (srcAttrs?[.size] as? NSNumber)?.intValue ?? -1
        let dstDirExists = fm.fileExists(atPath: box64InstallPath)
        Self.log("extractBox64: srcExists=\(srcExists) srcSize=\(srcSize) dstDirExists=\(dstDirExists)")
        guard streamCopy(src: bundledPath, dst: destination, fm: fm) else {
            throw SetupError.copyFailed("streamCopy returned false for \(bundledPath) -> \(destination) (srcExists=\(srcExists) srcSize=\(srcSize) dstDirExists=\(dstDirExists))")
        }
        guard let attrs = try? fm.attributesOfItem(atPath: destination),
              let size = attrs[.size] as? NSNumber, size.intValue > 0 else {
            try? fm.removeItem(atPath: destination)
            throw SetupError.copyFailed("extracted box64 is empty")
        }
        Self.log("extractBox64: OK (\(size.intValue) bytes)")
    }

    private func copyDirRecursive(src: String, dst: String, fm: FileManager) throws {
        try fm.createDirectory(atPath: dst, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: src).filter { $0 != ".gitkeep" }
        for item in contents {
            try autoreleasepool {
                let srcPath = (src as NSString).appendingPathComponent(item)
                let dstPath = (dst as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    guard streamCopy(src: srcPath, dst: dstPath, fm: fm) else {
                        throw SetupError.copyFailed("failed to copy \(item)")
                    }
                }
            }
        }
    }

    private func extractWine() throws {
        let fm = FileManager.default
        let wine64Dest = (wineInstallPath as NSString).appendingPathComponent("bin/wine64")
        if isNonEmptyFile(wine64Dest) { return }
        if fm.fileExists(atPath: wineInstallPath) {
            try? fm.removeItem(atPath: wineInstallPath)
            Self.log("extractWine: removed stale Wine directory (wine64 missing or 0 bytes)")
        }

        guard let bundledWineDir = findBundledResource("Wine", isDirectory: true) else {
            throw SetupError.wineMissing
        }

        try fm.createDirectory(atPath: wineInstallPath, withIntermediateDirectories: true)
        let contents = try fm.contentsOfDirectory(atPath: bundledWineDir).filter { $0 != ".gitkeep" }
        for item in contents {
            try autoreleasepool {
                let srcPath = (bundledWineDir as NSString).appendingPathComponent(item)
                let dstPath = (wineInstallPath as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    guard streamCopy(src: srcPath, dst: dstPath, fm: fm) else {
                        throw SetupError.copyFailed("failed to copy \(item) from Wine")
                    }
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
        let contents = try fm.contentsOfDirectory(atPath: bundledMVK).filter { $0 != ".gitkeep" }
        for item in contents {
            try autoreleasepool {
                let srcPath = (bundledMVK as NSString).appendingPathComponent(item)
                let dstPath = (mvkDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    guard streamCopy(src: srcPath, dst: dstPath, fm: fm) else {
                        throw SetupError.copyFailed("failed to copy \(item) from MoltenVK")
                    }
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
        let contents = try fm.contentsOfDirectory(atPath: bundledDXVK).filter { $0 != ".gitkeep" }
        for item in contents {
            try autoreleasepool {
                let srcPath = (bundledDXVK as NSString).appendingPathComponent(item)
                let dstPath = (dxvkDir as NSString).appendingPathComponent(item)
                var isDir: ObjCBool = false
                fm.fileExists(atPath: srcPath, isDirectory: &isDir)
                if isDir.boolValue {
                    try copyDirRecursive(src: srcPath, dst: dstPath, fm: fm)
                } else {
                    guard streamCopy(src: srcPath, dst: dstPath, fm: fm) else {
                        throw SetupError.copyFailed("failed to copy \(item) from DXVK")
                    }
                }
            }
        }
    }
}
