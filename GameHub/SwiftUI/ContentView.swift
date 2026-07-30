import SwiftUI

// DIAGNOSTIC stage 10d: testing if GameLibraryView.swift as a FILE
// (even with a trivial body) causes the crash. Creating a minimal
// inline child view instead.
struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        InlineGameView()
    }
}

struct InlineGameView: View {
    var body: some View {
        Text("Hello from inline")
    }
}
