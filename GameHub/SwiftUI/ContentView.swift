import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedTab = 0

    var body: some View {
        Text("Hello - ContentView works!")
            .onAppear { swiftLog("ContentView: Hello appeared!") }
    }
}
