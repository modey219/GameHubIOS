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
    var terminationStatus: Int32 = 0
    var terminationHandler: ((NativeProcess) -> Void)?

    private var pid: pid_t = 0
    private var _isRunning = false

    var processIdentifier: pid_t { pid }

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
        posix_spawn_file_actions_init(&fileActions)

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

        pid = localPid
        _isRunning = true

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            if (status & 0x7f) == 0 {
                self.terminationStatus = (status >> 8) & 0xff
            } else {
                self.terminationStatus = -1
            }
            self._isRunning = false
            DispatchQueue.main.async { self.terminationHandler?(self) }
        }
    }

    func waitUntilExit() {
        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            if (status & 0x7f) == 0 {
                terminationStatus = (status >> 8) & 0xff
            } else {
                terminationStatus = -1
            }
            _isRunning = false
        }
    }

    func terminate() {
        if pid > 0 && _isRunning {
            kill(pid, SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                if self?._isRunning == true, let pid = self?.pid { kill(pid, SIGKILL) }
            }
        }
    }

    var isRunning: Bool { _isRunning }

    deinit {
        if pid > 0 && _isRunning { kill(pid, SIGKILL) }
    }
}
