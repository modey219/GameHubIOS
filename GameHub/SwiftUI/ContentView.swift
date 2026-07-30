import SwiftUI

// DIAGNOSTIC stage 10c: GameLibraryView had @EnvironmentObject removed,
// body is still Text(""). Testing if the act of creating a child view
// with @EnvironmentObject was the trigger, vs any child view at all.
struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        GameLibraryView()
    }
}
