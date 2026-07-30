import SwiftUI
import UIKit

func setupCrashHandler() {
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

// DIAGNOSTIC stage 9: setupCrashHandler is innocent. Now testing
// whether the @StateObject initializations themselves are the culprit.
// Keep body as bare Text("Test") so no views consume these objects.
@main
struct GameHubApp: App {
    init() { setupCrashHandler() }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var setupManager = SetupManager()

    var body: some Scene {
        WindowGroup {
            Text("Test")
        }
    }
}

// DIAGNOSTIC stage 6: GameLibraryView body is already empty (Text("")),
// yet the scene-create watchdog still fires. The crash must originate
// ABOVE GameLibraryView. LaunchView has `if showSplash` - another
// "dynamic view" conditional - plus SF Symbols in splashView and an
// animated transition. This stage strips all of that: no splash, no
// conditional, no SF Symbols, no animation. Just ContentView directly.
struct LaunchView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var setupManager: SetupManager

    var body: some View {
        ContentView()
            .environmentObject(containerManager)
            .environmentObject(jitManager)
            .environmentObject(settingsManager)
            .environmentObject(setupManager)
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
