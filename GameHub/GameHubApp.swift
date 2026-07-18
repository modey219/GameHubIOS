import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(jitManager)
                .environmentObject(settingsManager)
                .onAppear { performSetup() }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                    jitManager.checkJITStatus()
                }
        }
    }

    private func performSetup() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let dirs = ["Box64", "Wine", "Wine/rootfs", "Containers", "Graphics", "Wine/input"]
        for dir in dirs {
            try? fm.createDirectory(at: docs.appendingPathComponent(dir), withIntermediateDirectories: true)
        }

        if !fm.fileExists(atPath: docs.appendingPathComponent("Graphics/MoltenVK").path) {
            try? fm.createDirectory(at: docs.appendingPathComponent("Graphics/MoltenVK"), withIntermediateDirectories: true)
        }

        GraphicsBridge.shared.initialize()

        let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/wine64").path)

        if box64Exists {
            Box64Bridge.shared.initialize()
        }
        if wineExists {
            WineBridge.shared.initialize()
        }
        if box64Exists && wineExists {
            WinePrefixManager.shared.initializePrefix()
        }

        settingsManager.applySettings()
    }
}
