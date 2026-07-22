import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        mainTabs
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            GameLibraryView()
                .tabItem { Label("Games", systemImage: "gamecontroller") }
                .tag(0)

            ContainerListView()
                .tabItem { Label("Containers", systemImage: "shippingbox") }
                .tag(1)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gear") }
                .tag(2)

            JITStatusView()
                .tabItem { Label("JIT", systemImage: "bolt.fill") }
                .tag(3)

            DebugView()
                .tabItem { Label("Debug", systemImage: "ladybug") }
                .tag(4)
        }
        .accentColor(.blue)
    }
}
