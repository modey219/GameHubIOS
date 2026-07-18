#if os(iOS)
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
}

class Process {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var terminationStatus: Int32 = 0
    var terminationHandler: ((Process) -> Void)?

    private var pid: pid_t = 0
    private var _isRunning = false

    init() {}

    func run() throws {
        guard let url = executableURL else {
            throw NSError(domain: "Process", code: -1, userInfo: [NSLocalizedDescriptionKey: "No executable URL"])
        }

        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw NSError(domain: "Process", code: -2, userInfo: [NSLocalizedDescriptionKey: "Not executable: \(url.path)"])
        }

        let path = url.path
        let args = arguments ?? []
        let env = environment ?? [:]

        var cArgs: [UnsafeMutablePointer<CChar>?] = [strdup(path)]
        for arg in args {
            cArgs.append(strdup(arg))
        }
        cArgs.append(nil)

        var cEnv: [UnsafeMutablePointer<CChar>?] = []
        for (key, value) in env {
            cEnv.append(strdup("\(key)=\(value)"))
        }
        cEnv.append(nil)

        var fileActions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&fileActions)

        var outReadFd: Int32 = -1
        var errReadFd: Int32 = -1

        if let outPipe = standardOutput as? iOSPipe {
            posix_spawn_file_actions_adddup2(&fileActions, outPipe.writeHandle.fileDescriptor, STDOUT_FILENO)
            posix_spawn_file_actions_addclose(&fileActions, outPipe.writeHandle.fileDescriptor)
            outReadFd = outPipe.readHandle.fileDescriptor
        }

        if let errPipe = standardError as? iOSPipe {
            posix_spawn_file_actions_adddup2(&fileActions, errPipe.writeHandle.fileDescriptor, STDERR_FILENO)
            posix_spawn_file_actions_addclose(&fileActions, errPipe.writeHandle.fileDescriptor)
            errReadFd = errPipe.readHandle.fileDescriptor
        }

        let result = posix_spawn(&pid, path, &fileActions, nil, cArgs, cEnv)

        for arg in cArgs { if let a = arg { free(a) } }
        for e in cEnv { if let v = e { free(v) } }
        posix_spawn_file_actions_destroy(&fileActions)

        guard result == 0 else {
            throw NSError(domain: "Process", code: Int(result),
                          userInfo: [NSLocalizedDescriptionKey: "posix_spawn failed: \(result)"])
        }

        _isRunning = true

        if let outPipe = standardOutput as? iOSPipe {
            outPipe.writeHandle.closeFile()
        }
        if let errPipe = standardError as? iOSPipe {
            errPipe.writeHandle.closeFile()
        }

        DispatchQueue.global().async { [weak self] in
            guard let self = self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            self.terminationStatus = Int32((status >> 8) & 0xFF)
            self._isRunning = false
            DispatchQueue.main.async {
                self.terminationHandler?(self)
            }
        }
    }

    func waitUntilExit() {
        if pid > 0 {
            var status: Int32 = 0
            waitpid(pid, &status, 0)
            terminationStatus = Int32((status >> 8) & 0xFF)
            _isRunning = false
        }
    }

    func terminate() {
        if pid > 0 && _isRunning {
            kill(pid, SIGTERM)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                if self._isRunning {
                    kill(self.pid, SIGKILL)
                }
            }
        }
    }

    var isRunning: Bool { return _isRunning }

    deinit {
        if pid > 0 && _isRunning {
            kill(pid, SIGKILL)
            waitpid(pid, nil, 0)
        }
    }
}
#endif
