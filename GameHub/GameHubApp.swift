import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()
    @StateObject private var downloadManager = RuntimeDownloadManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(containerManager)
                .environmentObject(jitManager)
                .environmentObject(settingsManager)
                .environmentObject(downloadManager)
                .onAppear {
                    setupApp()
                }
        }
    }

    private func setupApp() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        let box64Path = docs.appendingPathComponent("Box64/box64").path
        if fm.fileExists(atPath: box64Path) {
            Box64Bridge.shared.initialize()
        }

        let winePath = docs.appendingPathComponent("Wine/wine64").path
        if fm.fileExists(atPath: winePath) {
            WineBridge.shared.initialize()
        }

        GraphicsBridge.shared.initialize()

        if RuntimeDownloadManager.shared.isAllRequiredInstalled() {
            WinePrefixManager.shared.initializePrefix()
        }

        if jitManager.isJITEnabled {
            jitManager.enableJITlessMode()
        }
    }
}
