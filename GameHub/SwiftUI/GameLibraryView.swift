import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager

    var body: some View {
        NavigationStack {
            Text("GameLibraryView WORKS")
                .navigationTitle("Game Library")
        }
    }
}
