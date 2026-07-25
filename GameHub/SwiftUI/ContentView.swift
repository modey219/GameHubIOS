import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        // NOTE: intentionally not using TabView here. On some iOS versions
        // (observed on iOS 27 beta) TabView's internal body computation
        // (DefaultTabViewStyle/SystemTabViewStyle) can take 19+ seconds on
        // first render, tripping the "scene-create" watchdog and causing
        // the OS to kill the app (0x8BADF00D) before it ever appears.
        // Since we only have a single destination anyway, render it
        // directly instead of wrapping it in a TabView.
        GameLibraryView()
            .accentColor(.blue)
    }
}
