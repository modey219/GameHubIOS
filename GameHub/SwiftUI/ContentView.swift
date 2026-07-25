import SwiftUI

struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    // TEMPORARY DIAGNOSTIC BUILD:
    // We've hit the same 0x8BADF00D "scene-create watchdog" crash 3 times in a
    // row, each time with a DIFFERENT SwiftUI internal at the top of the stack
    // (TabView, then NavigationStack, then generic DynamicViewList/
    // DynamicContainerInfo) while CPU time/percentage stayed nearly identical
    // (~20s, ~17%) every time. That pattern means it's very unlikely to be one
    // specific "buggy" view - the watchdog is just catching AttributeGraph
    // wherever it happens to be at kill time. This minimal view removes ALL
    // of our custom view hierarchy (GameLibraryView, sheets, grids, etc.) to
    // determine whether the hang is in our SwiftUI code at all, or something
    // more fundamental (device/iOS 27 beta/LiveContainer). Once we know the
    // answer we'll restore the real UI.
    var body: some View {
        Text("Diagnostic build - if you see this, tap has worked")
            .font(.title2)
            .multilineTextAlignment(.center)
            .padding()
    }
}
