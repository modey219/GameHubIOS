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
        }
        .accentColor(.blue)
    }
}
