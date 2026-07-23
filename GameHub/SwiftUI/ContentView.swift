import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            Group {
                if selectedTab == 0 {
                    GameLibraryView()
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Games", systemImage: "gamecontroller") }
            .tag(0)

            Group {
                if selectedTab == 1 {
                    ContainerListView()
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Containers", systemImage: "cube") }
            .tag(1)

            Group {
                if selectedTab == 2 {
                    JITStatusView()
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("JIT", systemImage: "cpu") }
            .tag(2)

            Group {
                if selectedTab == 3 {
                    SettingsView()
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)

            Group {
                if selectedTab == 4 {
                    DebugView()
                } else {
                    Color.clear
                }
            }
            .tabItem { Label("Debug", systemImage: "ant") }
            .tag(4)
        }
        .accentColor(.blue)
        .onAppear { swiftLog("ContentView TabView appeared, selectedTab=\(selectedTab)") }
    }
}
