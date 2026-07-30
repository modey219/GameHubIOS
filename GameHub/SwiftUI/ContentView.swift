// DIAGNOSTIC stage 10b: ContentView + environment objects + GameLibraryView
// (with Text("") body) shows black screen then crashes. Isolating whether
// the issue is ContentView's own environment object resolution or
// GameLibraryView's.
struct ContentView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager

    var body: some View {
        Text("Test")
    }
}
