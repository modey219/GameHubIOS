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
        Box64Bridge.shared.initialize()
        WineBridge.shared.initialize()
        GraphicsBridge.shared.initialize()
        JITManager.shared.enableJIT()
    }
}
