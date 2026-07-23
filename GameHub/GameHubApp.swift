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
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(jitManager)
                .environmentObject(settingsManager)

            if showSplash {
                splashView
                    .transition(.opacity)
            }
        }
        .onAppear {
            performSetup()
            DispatchQueue.main.asyncAfter(deadline: .now() + 20) {
                withAnimation { showSplash = false }
            }
        }
    }

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("MN emulator").font(.largeTitle).bold()
            Text("PC Game Emulator for iPhone & iPad").font(.subheadline).foregroundColor(.secondary)
            Text("Created by @R_MOX").font(.caption).foregroundColor(.secondary)
            ProgressView().scaleEffect(1.2)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func performSetup() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                DispatchQueue.main.async { withAnimation { showSplash = false } }
                return
            }

            let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

            if alreadyLaunched && box64Exists && wineExists {
                DispatchQueue.main.async { withAnimation { showSplash = false } }
                return
            }

            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.synchronize()

            for stalePath in ["Box64/box64", "Wine/bin/wine64"] {
                let fullPath = docs.appendingPathComponent(stalePath).path
                if fm.fileExists(atPath: fullPath),
                   let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? NSNumber,
                   size.intValue == 0 {
                    try? fm.removeItem(atPath: fullPath)
                }
            }

            if !box64Exists || !wineExists {
                do {
                    try Box64Bridge.shared.setupAllBundledBinaries { _ in }
                } catch {
                    NSLog("[MNEmulator] extraction failed: \(error)")
                }
            }

            WineBridge.shared.initialize()
            WinePrefixManager.shared.initializePrefix()

            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            UserDefaults.standard.synchronize()
            DispatchQueue.main.async { withAnimation { showSplash = false } }
        }
    }
}
