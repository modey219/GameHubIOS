import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager

    var body: some View {
        Text("ContentView WORKS")
            .font(.largeTitle)
    }
}
