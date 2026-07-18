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
                .onAppear {
                    performSetup()
                }
        }
    }

    private func performSetup() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        let dirs = ["Box64", "Wine", "Wine/rootfs", "Containers", "Graphics", "Wine/input"]
        for dir in dirs {
            let path = docs.appendingPathComponent(dir)
            if !fm.fileExists(atPath: path.path) {
                try? fm.createDirectory(at: path, withIntermediateDirectories: true)
            }
        }

        GraphicsBridge.shared.initialize()

        let box64Path = docs.appendingPathComponent("Box64/box64").path
        let winePath = docs.appendingPathComponent("Wine/wine64").path
        let hasBinaries = fm.fileExists(atPath: box64Path) && fm.fileExists(atPath: winePath)

        if hasBinaries {
            Box64Bridge.shared.initialize()
            WineBridge.shared.initialize()
            WinePrefixManager.shared.initializePrefix()
        }

        jitManager.enableJITlessMode()
    }
}
