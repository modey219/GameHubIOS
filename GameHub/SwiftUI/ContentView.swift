import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            GameLibraryView()
                .tabItem { Label("Games", systemImage: "gamecontroller") }
                .tag(0)

            ContainerListView()
                .tabItem { Label("Containers", systemImage: "cube") }
                .tag(1)

            JITStatusView()
                .tabItem { Label("JIT", systemImage: "cpu") }
                .tag(2)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)

            DebugView()
                .tabItem { Label("Debug", systemImage: "ant") }
                .tag(4)
        }
        .accentColor(.blue)
        .onAppear { jitManager.setupOnce() }
}
