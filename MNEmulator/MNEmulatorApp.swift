import SwiftUI
import UIKit

func setupCrashHandler() {
    if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
        let stderrPath = path + "/stderr.log"
        if let file = fopen(stderrPath, "a") {
            dup2(fileno(file), STDERR_FILENO)
            fclose(file)
        }
    }
    NSSetUncaughtExceptionHandler { exception in
        let crash = "[Crash] ObjC exception: \(exception.name) reason=\(exception.reason ?? "nil") callStack=\(exception.callStackSymbols.joined(separator: "\n"))"
        NSLog("%@", crash)
        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let log = path + "/crash.log"
            try? crash.write(toFile: log, atomically: true, encoding: .utf8)
        }
    }
    if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
        let crashLogPath = path + "/crash.log"
        crashLogPath.withCString { install_crash_handler($0) }
        safeSetenv("CRASH_LOG_PATH", crashLogPath)
    }
}

private func writeDiag(_ s: String) {
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

// DIAGNOSTIC stage 10b: ContentView with @EnvironmentObject + bare
// Text("Test") body. Testing if the environment object resolution chain
// itself triggers the watchdog, or if it's something deeper in the view
// hierarchy.
@main
struct MNEmulatorApp: App {
    init() {
        setupCrashHandler()
        Box64Bridge.writeDiag("APP_BUILD kernel-svc-v379")
    }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var setupManager = SetupManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(jitManager)
                .environmentObject(settingsManager)
                .environmentObject(setupManager)
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
