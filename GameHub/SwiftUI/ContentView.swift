import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Text("Games Tab")
                .tabItem { Label("Games", systemImage: "gamecontroller") }
                .tag(0)

            Text("Containers Tab")
                .tabItem { Label("Containers", systemImage: "cube") }
                .tag(1)

            Text("JIT Tab")
                .tabItem { Label("JIT", systemImage: "cpu") }
                .tag(2)

            Text("Settings Tab")
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(3)

            Text("Debug Tab")
                .tabItem { Label("Debug", systemImage: "ant") }
                .tag(4)
        }
        .accentColor(.blue)
    }
}
