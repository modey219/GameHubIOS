#if os(iOS)
import Foundation

class Process {
    var executableURL: URL?
    var arguments: [String]?
    var environment: [String: String]?
    var standardOutput: Any?
    var standardError: Any?
    var terminationStatus: Int32 = 0
    var terminationHandler: ((Process) -> Void)?

    init() {}

    func run() throws {
        print("[iOS] Process.run() not available - \(executableURL?.lastPathComponent ?? "unknown")")
    }

    func waitUntilExit() {}
}
#endif
