import Foundation

class iOSPipe {
    let readHandle: FileHandle
    let writeHandle: FileHandle

    init?() {
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else { return nil }
        readHandle = FileHandle(fileDescriptor: fds[0], closeOnDealloc: true)
        writeHandle = FileHandle(fileDescriptor: fds[1], closeOnDealloc: true)
    }

    func readOutput(timeout: TimeInterval = 2.0) -> String {
        writeHandle.closeFile()
        let data = readHandle.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? "(binary output)"
    }
}

class NativeProcess {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var terminationHandler: ((NativeProcess) -> Void)?

    private let lock = NSLock()
    private var _terminationStatus: Int32 = 0
    private var _pid: pid_t = 0
    private var _isRunning = false
    private var _finished = false
    private var _finishedCond = NSCondition()

    var terminationStatus: Int32 {
        lock.lock(); defer { lock.unlock() }
        return _terminationStatus
    }

    var processIdentifier: pid_t {
        lock.lock(); defer { lock.unlock() }
        return _pid
    }

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    init() {}

    func run() throws {
        guard let url = executableURL else {
            throw NSError(domain: "Process", code: -1, userInfo: [NSLocalizedDescriptionKey: "No executable URL set"])
        }

        let path = url.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw NSError(domain: "Process", code: -2, userInfo: [NSLocalizedDescriptionKey: "Binary not found: \(path)"])
        }

        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        if let perm = attrs?[.posixPermissions] as? Int {
            if perm & 0o111 == 0 {
                try? FileManager.default.setAttributes([.posixPermissions: perm | 0o755], ofItemAtPath: path)
            }
        }

        let args = arguments ?? []
        let env = environment ?? [:]

        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(path)]
        for arg in args { cArgs.append(strdup(arg)) }
        cArgs.append(nil)

        var cEnv: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            cEnv.append(strdup("\(key)=\(value)"))
        }
        cEnv.append(nil)

        var fileActions: posix_spawn_file_actions_t?
        let initResult = posix_spawn_file_actions_init(&fileActions)
        guard initResult == 0, fileActions != nil else {
            for arg in cArgs { if let a = arg { free(a) } }
            for e in cEnv { if let v = e { free(v) } }
            throw NSError(domain: "Process", code: Int(initResult),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawn_file_actions_init failed (\(initResult))"])
        }

        var outFd: Int32 = -1
        var errFd: Int32 = -1

        if let outPipe = standardOutput as? iOSPipe {
            outFd = outPipe.writeHandle.fileDescriptor
            posix_spawn_file_actions_adddup2(&fileActions, outFd, STDOUT_FILENO)
            posix_spawn_file_actions_addclose(&fileActions, outFd)
        }
        if let errPipe = standardError as? iOSPipe {
            errFd = errPipe.writeHandle.fileDescriptor
            posix_spawn_file_actions_adddup2(&fileActions, errFd, STDERR_FILENO)
            posix_spawn_file_actions_addclose(&fileActions, errFd)
        }

        var localPid: pid_t = 0
        let result = posix_spawn(&localPid, path, &fileActions, nil, cArgs, cEnv)

        for arg in cArgs { if let a = arg { free(a) } }
        for e in cEnv { if let v = e { free(v) } }
        posix_spawn_file_actions_destroy(&fileActions)

        guard result == 0 else {
            let errStr = String(cString: strerror(result))
            throw NSError(domain: "Process", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawn failed (\(result)): \(errStr)\nBinary: \(path)"])
        }

        lock.lock()
        _pid = localPid
        _isRunning = true
        lock.unlock()

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            waitpid(localPid, &status, 0)
            self.lock.lock()
            if (status & 0x7f) == 0 {
                self._terminationStatus = (status >> 8) & 0xff
            } else {
                self._terminationStatus = -1
            }
            self._isRunning = false
            self.lock.unlock()
            self._finishedCond.lock()
            self._finished = true
            self._finishedCond.signal()
            self._finishedCond.unlock()
            DispatchQueue.main.async { self.terminationHandler?(self) }
        }
    }

    func waitUntilExit() {
        _finishedCond.lock()
        while !_finished {
            _finishedCond.wait()
        }
        _finishedCond.unlock()
    }

    func terminate() {
        let (pid, running): (pid_t, Bool) = {
            lock.lock(); defer { lock.unlock() }
            return (_pid, _isRunning)
        }()
        if pid > 0 && running {
            kill(pid, SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self = self else { return }
                self.lock.lock()
                let stillRunning = self._isRunning
                let curPid = self._pid
                self.lock.unlock()
                if stillRunning { kill(curPid, SIGKILL) }
            }
        }
    }

    deinit {
        let (pid, running): (pid_t, Bool) = {
            lock.lock(); defer { lock.unlock() }
            return (_pid, _isRunning)
        }()
        if pid > 0 && running { kill(pid, SIGKILL) }
    }
}
