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

@main
struct GameHubApp: App {
    init() { setupCrashHandler() }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var setupManager = SetupManager()

    var body: some Scene {
        WindowGroup {
            LaunchView(
                containerManager: containerManager,
                jitManager: jitManager,
                settingsManager: settingsManager,
                setupManager: setupManager
            )
        }
    }
}

struct LaunchView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var setupManager: SetupManager
    @State private var showSplash = true

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showSplash {
                splashView
                    .transition(.opacity)
            } else {
                ContentView()
                    .environmentObject(containerManager)
                    .environmentObject(jitManager)
                    .environmentObject(settingsManager)
                    .environmentObject(setupManager)
                    .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                        jitManager.checkJITStatus()
                    }
            }
        }
        .onAppear {
            performSetup()
        }
    }

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

            Text("MN emulator")
                .font(.largeTitle).bold()

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline).foregroundColor(.secondary)

            Text("Created by @R_MOX")
                .font(.caption).foregroundColor(.secondary)

            VStack(spacing: 8) {
                ProgressView()
                    .scaleEffect(1.2)
                Text("Loading...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }

    private func performSetup() {
        writeDiag("step=start")
        UserDefaults.standard.set(false, forKey: "_crash_sentinel")
        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        writeDiag("step=done")

        setupManager.checkReady()

        withAnimation(.easeInOut(duration: 0.5)) {
            showSplash = false
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
