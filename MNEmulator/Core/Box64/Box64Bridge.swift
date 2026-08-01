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
    private static let logDateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        return f
    }()

    static func log(_ msg: String) {
        let ts = logDateFormatter.string(from: Date())
        let line = "[\(ts)] \(msg)\n"
        logQueue.sync {
            if let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
                let path = p + "/swift_box64.log"
                if let fh = FileHandle(forWritingAtPath: path) {
                    fh.seekToEndOfFile()
                    fh.write(line.data(using: .utf8)!)
                    fh.closeFile()
                } else {
                    try? line.write(toFile: path, atomically: true, encoding: .utf8)
                }
            }
        }
    }

    static func writeDiag(_ s: String) {
        if let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let line = "[\(Date().timeIntervalSince1970)] \(s)\n"
            let path = p + "/diag.log"
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(line.data(using: .utf8)!)
                fh.closeFile()
            } else {
                try? line.write(toFile: path, atomically: true, encoding: .utf8)
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

        Self.writeDiag("setup_start")
        NSLog("[MNEmulator] extraction start")

        progressCallback?("Extracting Box64...")
        NSLog("[MNEmulator] extractBox64 start")
        Self.writeDiag("extractBox64_start")
        try autoreleasepool { try self.extractBox64() }
        NSLog("[MNEmulator] extractBox64 done")
        Self.writeDiag("extractBox64_done")

        progressCallback?("Extracting Wine...")
        NSLog("[MNEmulator] extractWine start")
        Self.writeDiag("extractWine_start")
        try autoreleasepool {
            try self.extractWine { detail in
                progressCallback?(detail)
            }
        }
        NSLog("[MNEmulator] extractWine done")
        Self.writeDiag("extractWine_done")

        progressCallback?("Skipping optional graphics (MoltenVK/DXVK)...")
        NSLog("[MNEmulator] skipping MoltenVK + DXVK extraction (not needed for launch)")

        progressCallback?("All extractions complete")
        NSLog("[MNEmulator] all extraction done")
        Self.writeDiag("setup_done")
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

        let docsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.path ?? "/tmp"
        docsPath.withCString { set_c_diag_docs_path($0) }
        Self.writeDiag("init_start")
        Self.writeDiag("docsPath=\(docsPath)")
        Self.writeDiag("box64InstallPath=\(box64InstallPath)")
        Self.writeDiag("wineInstallPath=\(wineInstallPath)")
        Self.writeDiag("HOME_wine=\(wineInstallPath)")
        Self.writeDiag("CRASH_LOG=\(docsPath)/crash.log")

        Self.writeDiag("step1: calloc")
        Self.writeDiag("c_diag_test_exists=\(FileManager.default.fileExists(atPath: docsPath + "/c_diag_test.txt"))")
        Self.writeDiag("probe_magic=\(box64_probe_magic())")
        let homePath = NSHomeDirectory()
        Self.writeDiag("NSHomeDirectory=\(homePath)")
        let probePtr = UnsafeMutablePointer<CChar>.allocate(capacity: 32768)
        probePtr.initialize(repeating: 0, count: 32768)
        let probeSem = DispatchSemaphore(value: 0)
        let probeThread = Thread {
            docsPath.withCString { d in
                Bundle.main.bundlePath.withCString { b in
                    NSTemporaryDirectory().withCString { t in
                        homePath.withCString { h in
                            box64_probe_paths(d, b, t, h, probePtr, 32768)
                        }
                    }
                }
            }
            probeSem.signal()
        }
        probeThread.name = "mn-probe"
        probeThread.stackSize = 2 << 20
        probeThread.start()
        let timedOut = probeSem.wait(timeout: .now() + 20) == .timedOut
        if timedOut {
            Self.writeDiag("PROBE TIMEOUT (20s) — continuing without probe data")
        }
        let probeText = String(cString: probePtr)
        if !probeText.isEmpty {
            Self.writeDiag("PROBE BUFFER (partial \(probeText.count) chars):\n\(probeText)")
        } else {
            Self.writeDiag("PROBE BUFFER: (empty)")
        }
        if !timedOut {
            let probeFiles = [
                ("docs", docsPath + "/box64_probe.log"),
                ("tmpdir", NSTemporaryDirectory() + "/box64_probe.log"),
                ("/tmp", "/tmp/box64_probe.log"),
                ("home", homePath + "/box64_probe.log"),
            ]
            for (label, path) in probeFiles {
                if let data = FileManager.default.contents(atPath: path),
                   let content = String(data: data, encoding: .utf8), !content.isEmpty {
                    Self.writeDiag("PROBE FILE [\(label)] \(path):\n\(content)")
                } else {
                    Self.writeDiag("PROBE FILE [\(label)] \(path): (missing)")
                }
            }
        }
        let traceSnap = UnsafeMutablePointer<CChar>.allocate(capacity: 32768)
        traceSnap.initialize(repeating: 0, count: 32768)
        box64_probe_trace_snapshot(traceSnap, 32768)
        let snapText = String(cString: traceSnap)
        if !snapText.isEmpty {
            Self.writeDiag("PROBE TRACE (snapshot \(snapText.count) chars):\n\(snapText)")
        } else {
            Self.writeDiag("PROBE TRACE (snapshot): (empty)")
        }
        traceSnap.deallocate()
        if let trace = FileManager.default.contents(atPath: docsPath + "/probe_trace.log"),
           let traceText = String(data: trace, encoding: .utf8), !traceText.isEmpty {
            Self.writeDiag("PROBE TRACE FILE:\n\(traceText)")
        } else {
            Self.writeDiag("PROBE TRACE FILE: (missing)")
        }
        probePtr.deinitialize(count: 32768)
        probePtr.deallocate()
        let localCtx = autoreleasepool { () -> UnsafeMutablePointer<box64_context_t>? in
            box64_create_step1()
        }
        Self.writeDiag("step1: result=\(localCtx != nil ? "OK" : "NULL")")
        guard let localCtx = localCtx else {
            Self.log("box64_create_step1 returned NULL!")
            lock.unlock()
            return
        }

        Self.writeDiag("step2a: syscall_emulator_create_alloc")
        let step2aResult = autoreleasepool { () -> Int32 in
            box64_create_step2a(localCtx)
        }
        Self.writeDiag("step2a: result=\(step2aResult)")
        if step2aResult != 0 {
            Self.log("box64_create_step2a FAILED: \(step2aResult)")
            box64_destroy(localCtx)
            lock.unlock()
            return
        }

        Self.writeDiag("step2b: syscall_emulator_create_init")
        let step2bResult = autoreleasepool { () -> Int32 in
            box64_create_step2b(localCtx)
        }
        Self.writeDiag("step2b: result=\(step2bResult)")
        if step2bResult != 0 {
            Self.log("box64_create_step2b FAILED: \(step2bResult)")
            box64_destroy(localCtx)
            lock.unlock()
            return
        }

        Self.writeDiag("step3: set_context + g_box64")
        box64_create_step3(localCtx)
        Self.writeDiag("step3: DONE")

        Self.writeDiag("calling box64_init...")
        let initResult = box64_init(localCtx, box64InstallPath)
        Self.writeDiag("box64_init result=\(initResult)")
        Self.log("box64_init returned \(initResult)")
        if initResult == 0 {
            ctx = localCtx
            isInitialized = true
        } else {
            Self.log("box64_init FAILED — destroying context")
            box64_destroy(localCtx)
        }

        lock.unlock()
        Self.writeDiag("initialize_done isInitialized=\(isInitialized)")
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

        Self.writeDiag("launchWine_start")
        lock.lock()
        if !isInitialized || ctx == nil {
            lock.unlock()
            Self.log("Box64 not initialized yet, initializing now...")
            Self.writeDiag("launchWine_calling_initialize")
            initialize()
            Self.writeDiag("launchWine_init_done isInitialized=\(isInitialized)")
            lock.lock()
            guard isInitialized else {
                lock.unlock()
                Self.log("ERROR: Box64 auto-init failed")
                Self.writeDiag("launchWine_init_failed")
                result.error = "Box64 initialization failed. Please restart the app."
                return result
            }
        } else {
            Self.writeDiag("launchWine_already_initialized")
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

        Self.writeDiag("launchWine_env_set")
        Self.log("calling box64_set_wine_path/set_prefix/set_game...")
        box64_set_wine_path(ctx, wine64Path)
        box64_set_prefix(ctx, containerPath)
        box64_set_game(ctx, executablePath)
        Self.writeDiag("launchWine_fs_audit_start")
        auditPath(wine64Path, label: "wine64")
        auditPath(wineInstallPath, label: "wine_dir")
        auditDirContents((wineInstallPath as NSString).appendingPathComponent("bin"), label: "wine/bin")
        auditDirContents((wineInstallPath as NSString).appendingPathComponent("lib"), label: "wine/lib")
        auditDirContents((wineInstallPath as NSString).appendingPathComponent("lib/wine64"), label: "wine/lib/wine64")
        auditPath(box64InstallPath + "/box64", label: "box64_bin")

        let tmpDir = NSTemporaryDirectory()
        let realDocs = (tmpDir as NSString).appendingPathComponent("../Documents")
        auditPath(realDocs, label: "real_container_Documents(tmp/../Documents)")
        auditDirContents(realDocs, label: "real_container_Documents_entries")
        Self.writeDiag("TMPDIR_real=\(tmpDir)")
        Self.writeDiag("realDocs_candidate=\(realDocs)")
        self.auditMagicBytes(wine64Path, label: "wine64_magic")
        self.auditMagicBytes((wineInstallPath as NSString).appendingPathComponent("loader/wine64"), label: "loader_wine64_magic")
        self.auditMagicBytes((wineInstallPath as NSString).appendingPathComponent("lib64/wine64"), label: "lib64_wine64_magic")
        Self.writeDiag("launchWine_fs_audit_end")
        Self.log("calling box64_launch_wine(), memory = \(Self.memoryUsageMB())MB...")
        Self.writeDiag("box64_launch_enter")
        let rc: Int32 = autoreleasepool { box64_launch_wine(ctx, executablePath, nil) }
        Self.writeDiag("box64_launch_exit rc=\(rc) errno=\(errno)")
        Self.log("box64_launch_wine returned \(rc), memory = \(Self.memoryUsageMB())MB")
        if rc != 0 {
            let cError = box64_get_wine_error()
            let errStr = cError.map { String(cString: $0) } ?? ""
            Self.log("ERROR: box64_launch_wine failed: \(errStr)")
            lock.unlock()
            result.error = "Failed to launch Box64+Wine (error \(rc)):\n\(errStr)\n\n" +
                "Binary: \(wine64Path)\n" +
                "Exe: \(executablePath)\n\n" +
                "Box64 could not launch Wine. Check the error above for the exact cause."
            return result
        }

        Self.log("launchWine SUCCESS")
        _isRunning = true
        lock.unlock()
        Self.writeDiag("launchWine_success")
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
            docs.appendingPathComponent("Wine/box64_runner.log").path,
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

    private func auditPath(_ path: String, label: String) {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDir)
        var info = "FS-AUDIT \(label) path=\(path) exists=\(exists)"
        if exists { info += " isDir=\(isDir.boolValue)" }
        if let attrs = try? fm.attributesOfItem(atPath: path) {
            if let sz = attrs[FileAttributeKey.size] as? NSNumber { info += " size=\(sz.intValue)" }
            if let type = attrs[FileAttributeKey.type] as? FileAttributeType { info += " type=\(type.rawValue)" }
            if let perm = attrs[FileAttributeKey.posixPermissions] as? NSNumber { info += " perm=\(String(format: "0%o", perm.intValue))" }
        }
        if let dest = try? fm.destinationOfSymbolicLink(atPath: path) {
            info += " isSymlink=true target=\(dest)"
        }
        Self.writeDiag(info)
        Self.log(info)
    }

    private func auditDirContents(_ path: String, label: String, limit: Int = 80) {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else {
            Self.writeDiag("FS-AUDIT \(label) dir=\(path) listing=(failed)")
            return
        }
        let shown = items.sorted().prefix(limit).joined(separator: ", ")
        Self.writeDiag("FS-AUDIT \(label) dir=\(path) count=\(items.count) [\(shown)]")
    }

    private func auditMagicBytes(_ path: String, label: String) {
        let fm = FileManager.default
        guard let data = fm.contents(atPath: path) else {
            Self.writeDiag("FS-AUDIT \(label) path=\(path) read=(failed)")
            return
        }
        let shown = Array(data.prefix(16))
        let hex = shown.map { String(format: "%02x", $0) }.joined(separator: " ")
        let ascii = shown.map { (0x20...0x7e).contains($0) ? String(UnicodeScalar(UInt32($0))) : "." }.joined()
        Self.writeDiag("FS-AUDIT \(label) path=\(path) size=\(data.count) head=[\(hex)] \"\(ascii)\"")
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

    private func extractWine(progressCallback: ((String) -> Void)? = nil) throws {
        let fm = FileManager.default
        let wine64Dest = (wineInstallPath as NSString).appendingPathComponent("bin/wine64")
        if isNonEmptyFile(wine64Dest) {
            Self.log("extractWine: wine64 already exists and non-empty, skipping")
            Self.writeDiag("extractWine: already_done")
            return
        }

        guard let bundledWineDir = findBundledResource("Wine", isDirectory: true) else {
            Self.writeDiag("extractWine: bundled Wine directory NOT FOUND in app bundle")
            throw SetupError.wineMissing
        }
        Self.writeDiag("extractWine: source=\(bundledWineDir)")

        try fm.createDirectory(atPath: wineInstallPath, withIntermediateDirectories: true)

        var copied = 0
        var skipped = 0
        var failed = 0
        try copyDirectoryRecursive(src: bundledWineDir, dst: wineInstallPath, fm: fm, copied: &copied, skipped: &skipped, failed: &failed, progressCallback: progressCallback)
        Self.writeDiag("extractWine: done copied=\(copied) skipped=\(skipped) failed=\(failed)")

        let binaries = ["bin/wine", "bin/wine64", "bin/wineserver", "bin/wineboot"]
        for bin in binaries {
            let binPath = (wineInstallPath as NSString).appendingPathComponent(bin)
            if fm.fileExists(atPath: binPath) {
                try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binPath)
            }
        }
    }

    private func copyDirectoryRecursive(src: String, dst: String, fm: FileManager, copied: inout Int, skipped: inout Int, failed: inout Int, progressCallback: ((String) -> Void)? = nil) throws {
        let srcURL = URL(fileURLWithPath: src)
        let dstURL = URL(fileURLWithPath: dst)

        let files = (try? fm.contentsOfDirectory(at: srcURL, includingPropertiesForKeys: nil, options: .includesDirectoriesPostOrder)) ?? []
        let dirs = (try? fm.contentsOfDirectory(at: srcURL, includingPropertiesForKeys: [.isDirectoryKey], options: [])) ?? []

        func copyItemRecursive(_ srcItem: URL, _ dstItem: URL) throws {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: srcItem.path, isDirectory: &isDir) else { return }

            if isDir.boolValue {
                try? fm.createDirectory(at: dstItem, withIntermediateDirectories: true)
                let children = (try? fm.contentsOfDirectory(at: srcItem, includingPropertiesForKeys: nil)) ?? []
                for child in children {
                    let childDst = dstItem.appendingPathComponent(child.lastPathComponent)
                    try copyItemRecursive(child, childDst)
                }
            } else {
                if fm.fileExists(atPath: dstItem.path),
                   let attrs = try? fm.attributesOfItem(atPath: dstItem.path),
                   let size = attrs[.size] as? NSNumber, size.intValue > 0 {
                    skipped += 1
                    return
                }
                do {
                    try fm.copyItem(at: srcItem, to: dstItem)
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dstItem.path)
                    copied += 1
                    if copied % 10 == 0 {
                        let msg = "Copying files: \(copied) done..."
                        progressCallback?(msg)
                        Self.log("extractWine: \(msg)")
                    }
                } catch {
                    failed += 1
                    Self.log("extractWine: failed to copy \(srcItem.path): \(error)")
                }
            }
        }

        try copyItemRecursive(srcURL, dstURL)
    }

    private func extractMoltenVK() throws {
        let fm = FileManager.default
        let mvkDir = (graphicsInstallPath as NSString).appendingPathComponent("MoltenVK")
        let mvkDest = mvkDir + "/libMoltenVK.dylib"
        if fm.fileExists(atPath: mvkDest) {
            let attrs = try? fm.attributesOfItem(atPath: mvkDest)
            let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
            if size > 0 { return }
        }

        guard let bundledMVK = findBundledResource("MoltenVK", isDirectory: true) else { return }
        try fm.createDirectory(atPath: mvkDir, withIntermediateDirectories: true)
        var copied = 0, skipped = 0, failed = 0
        try copyDirectoryRecursive(src: bundledMVK, dst: mvkDir, fm: fm, copied: &copied, skipped: &skipped, failed: &failed)
        Self.writeDiag("extractMoltenVK: done copied=\(copied) skipped=\(skipped) failed=\(failed)")
    }

    private func extractDXVK() throws {
        let fm = FileManager.default
        let dxvkDir = (graphicsInstallPath as NSString).appendingPathComponent("DXVK")
        if let contents = try? fm.contentsOfDirectory(atPath: dxvkDir), !contents.isEmpty {
            Self.writeDiag("extractDXVK: already_done \(contents.count) files")
            return
        }

        guard let bundledDXVK = findBundledResource("DXVK", isDirectory: true) else {
            Self.writeDiag("extractDXVK: bundled DXVK NOT FOUND, skipping")
            return
        }
        try fm.createDirectory(atPath: dxvkDir, withIntermediateDirectories: true)
        var copied = 0, skipped = 0, failed = 0
        try copyDirectoryRecursive(src: bundledDXVK, dst: dxvkDir, fm: fm, copied: &copied, skipped: &skipped, failed: &failed)
        Self.writeDiag("extractDXVK: done copied=\(copied) skipped=\(skipped) failed=\(failed)")
    }
}
