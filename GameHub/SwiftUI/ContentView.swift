import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0
    @State private var showJITAlert = false

    var body: some View {
        TabView(selection: $selectedTab) {
            GameLibraryView()
                .tabItem {
                    Label("Games", systemImage: "gamecontroller")
                }
                .tag(0)

            ContainerListView()
                .tabItem {
                    Label("Containers", systemImage: "shippingbox")
                }
                .tag(1)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
                .tag(2)

            JITStatusView()
                .tabItem {
                    Label("JIT", systemImage: "bolt.fill")
                }
                .tag(3)
        }
        .accentColor(.blue)
        .onAppear {
            checkJITStatus()
        }
        .alert("JIT Not Enabled", isPresented: $showJITAlert) {
            Button("Enable JIT") {
                jitManager.enableJIT()
            }
            Button("Continue Without JIT", role: .cancel) {
                jitManager.enableJITlessMode()
            }
        } message: {
            Text("JIT is required for optimal performance. Would you like to enable it via StikDebug?")
        }
    }

    private func checkJITStatus() {
        jitManager.requestJITIfNeeded { enabled in
            if !enabled {
                showJITAlert = true
            }
        }
    }
}
