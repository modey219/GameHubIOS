import SwiftUI
import UIKit

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()

    var body: some Scene {
        WindowGroup {
            VStack {
                Text("ContainerManager OK - \(containerManager.containers.count) containers")
                Text("JITManager OK - \(jitManager.statusMessage)")
            }
                .font(.largeTitle)
        }
    }
}
