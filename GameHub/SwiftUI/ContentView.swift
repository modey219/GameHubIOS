import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            if !setupManager.isSetupComplete {
                SetupBanner(message: setupManager.setupMessage, progress: setupManager.setupProgress)
            }

            TabView(selection: $selectedTab) {
                GameLibraryView()
                    .tabItem { Label("Games", systemImage: "gamecontroller") }
                    .tag(0)
            }
            .accentColor(.blue)
        }
    }
}

struct SetupBanner: View {
    let message: String
    let progress: Double

    var body: some View {
        VStack(spacing: 4) {
            ProgressView(value: progress)
                .progressViewStyle(.linear)
                .tint(.blue)
            Text(message)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }
}
