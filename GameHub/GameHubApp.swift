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

@main
struct GameHubApp: App {
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
            swiftLog("performSetup: no docs dir, returning")
            return
        }

        let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

        swiftLog("performSetup: alreadyLaunched=\(alreadyLaunched) box64=\(box64Exists) wine=\(wineExists)")

        if alreadyLaunched && box64Exists && wineExists {
            swiftLog("performSetup: binaries exist, returning early")
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
            swiftLog("performSetup: starting extraction...")
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    swiftLog("performSetup: extraction dispatch started")
                    do {
                        try Box64Bridge.shared.setupAllBundledBinaries { msg in
                            swiftLog("performSetup: extraction: \(msg)")
                        }
                        swiftLog("performSetup: extraction succeeded")
                    } catch {
                        swiftLog("performSetup: extraction FAILED: \(error)")
                    }
                    continuation.resume()
                }
            }
        }

        swiftLog("performSetup: starting WineBridge.initialize...")
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                swiftLog("performSetup: WineBridge dispatch")
                WineBridge.shared.initialize()
                swiftLog("performSetup: WinePrefixManager dispatch")
                WinePrefixManager.shared.initializePrefix()
                swiftLog("performSetup: saving hasLaunchedBefore")
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                UserDefaults.standard.synchronize()
                swiftLog("performSetup: DONE")
                continuation.resume()
            }
        }
    }
}
