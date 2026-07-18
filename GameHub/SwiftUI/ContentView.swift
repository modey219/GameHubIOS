import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0
    @State private var showWelcome = true

    var body: some View {
        Group {
            if showWelcome {
                WelcomeView()
            } else {
                mainTabView
            }
        }
        .onAppear {
            checkFirstLaunch()
        }
    }

    private var mainTabView: some View {
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
    }

    private func checkFirstLaunch() {
        let hasLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if hasLaunched {
            showWelcome = false
        } else {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/wine64").path)

            if box64Exists && wineExists {
                showWelcome = false
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            }
        }
    }
}
