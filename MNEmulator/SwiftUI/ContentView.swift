import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    var body: some View {
        Group {
            if hasLaunchedBefore {
                GameLibraryView()
            } else {
                SetupView()
            }
        }
    }
}
