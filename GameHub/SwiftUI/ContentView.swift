import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    // DIAGNOSTIC BUILD - stage 2:
    // Stage 1 (bare Text, no GameLibraryView at all) rendered successfully -
    // confirmed the crash is caused by something in our view code, not the
    // device/iOS 27 beta/LiveContainer. Now testing GameLibraryView with its
    // conditional (Group { if filteredGames.isEmpty {...} else {...} }) and
    // ForEach/gameGrid temporarily removed, to isolate whether SwiftUI's
    // "dynamic view" diffing machinery (DynamicViewList/DynamicContainerInfo -
    // seen at the top of the 3rd crash's stack trace) is the actual culprit.
    var body: some View {
        GameLibraryView()
            .accentColor(.blue)
    }
}
