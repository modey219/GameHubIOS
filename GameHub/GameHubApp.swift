import SwiftUI
import UIKit

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()

    var body: some Scene {
        WindowGroup {
            Text("ContainerManager OK - \(containerManager.containers.count) containers")
                .font(.largeTitle)
        }
    }
}
