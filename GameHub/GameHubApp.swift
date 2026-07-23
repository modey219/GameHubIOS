import SwiftUI
import UIKit

func swiftLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let path = docs.appendingPathComponent("app_flow.log").path
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        if let data = line.data(using: .utf8) { fh.write(data) }
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

func setupCrashHandler() {
    NSSetUncaughtExceptionHandler { exception in
        let crash = "[Crash] ObjC exception: \(exception.name) reason=\(exception.reason ?? "nil") callStack=\(exception.callStackSymbols.joined(separator: "\n"))"
        NSLog("%@", crash)
        swiftLog(crash)
    }
}

@main
struct GameHubApp: App {
    init() {
        swiftLog("=== App init START ===")
        setupCrashHandler()
        swiftLog("=== App init DONE ===")
    }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            RootView(containerManager: containerManager, jitManager: jitManager, settingsManager: settingsManager)
                .onAppear { swiftLog("RootView appeared") }
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
                    .onAppear { swiftLog("ContentView appeared inside RootView") }
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
                .onAppear { swiftLog("Splash screen appeared") }
            }
        }
        .task {
            swiftLog("RootView .task START")
            await performSetup()
            swiftLog("RootView .task DONE, setting showContent=true")
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

        if alreadyLaunched && box64Exists && wineExists {
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
