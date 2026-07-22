import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    var body: some View {
        if !hasLaunchedBefore {
            WelcomeView(onComplete: {
                hasLaunchedBefore = true
            })
        } else {
            mainTabs
        }
    }

    private var mainTabs: some View {
        TabView(selection: $selectedTab) {
            GameLibraryView()
                .tabItem { Label("Games", systemImage: "gamecontroller") }
                .tag(0)
        }
        .accentColor(.blue)
    }
}
