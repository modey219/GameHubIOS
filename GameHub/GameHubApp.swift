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
        } else {
            print("[App] Box64 binary not found at \(box64Path)")
        }

        let winePath = docs.appendingPathComponent("Wine/wine64").path
        if fm.fileExists(atPath: winePath) {
            WineBridge.shared.initialize()
        } else {
            print("[App] Wine binary not found at \(winePath)")
        }

        GraphicsBridge.shared.initialize()
        jitManager.enableJITlessMode()
    }
}
