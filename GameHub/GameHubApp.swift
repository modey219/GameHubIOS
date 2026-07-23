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

@main
struct GameHubApp: App {
    init() { setupCrashHandler() }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            RootView(containerManager: containerManager, jitManager: jitManager, settingsManager: settingsManager)
        }
    }
}

struct RootView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var showContent = false

    var body: some View {
        VStack {
            if showContent {
                Text("CONTENT IS SHOWING!")
                    .font(.largeTitle)
            } else {
                Text("STILL LOADING...")
                    .font(.largeTitle)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            showContent = true
        }
    }
}
