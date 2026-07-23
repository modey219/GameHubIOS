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
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showContent {
                ContentView()
                    .environmentObject(containerManager)
                    .environmentObject(jitManager)
                    .environmentObject(settingsManager)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("MN emulator").font(.largeTitle).bold()
                    Text("PC Game Emulator for iPhone & iPad").font(.subheadline).foregroundColor(.secondary)
                    Text("Created by @R_MOX").font(.caption).foregroundColor(.secondary)
                    ProgressView().scaleEffect(1.2)
                }
            }
        }
        .task {
            await performSetup()
            showContent = true
        }
    }

    @MainActor
    private func performSetup() async {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            return
        }

        let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

        if alreadyLaunched && box64Exists && wineExists { return }

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
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try Box64Bridge.shared.setupAllBundledBinaries { _ in }
                    } catch {
                        NSLog("[RootView] extraction failed: \(error)")
                    }
                    continuation.resume()
                }
            }
        }

        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                WineBridge.shared.initialize()
                WinePrefixManager.shared.initializePrefix()
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                UserDefaults.standard.synchronize()
                continuation.resume()
            }
        }
    }
}
