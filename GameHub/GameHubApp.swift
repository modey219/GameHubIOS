import SwiftUI
import UIKit

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            RootView(containerManager: containerManager, jitManager: jitManager, settingsManager: settingsManager)
        }
    }
}

struct RootView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var showContent = false

    var body: some View {
        VStack {
            if showContent {
                Text("CONTENT IS SHOWING!")
                    .font(.largeTitle)
            } else {
                Text("STILL LOADING...")
                    .font(.largeTitle)
                    .foregroundColor(.red)
            }
        }
        .onAppear {
            NSLog("[ROOTVIEW] onAppear fired")
            showContent = true
            NSLog("[ROOTVIEW] showContent set to: \(showContent)")
        }
    }
}
