import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager

    var body: some View {
        NavigationStack {
            if containerManager.containers.isEmpty {
                VStack(spacing: 20) {
                    Image(systemName: "gamecontroller")
                        .font(.system(size: 60)).foregroundColor(.gray)
                    Text("No Games Yet").font(.title2).bold()
                    Text("Import or add PC games to start playing").foregroundColor(.secondary)
                }
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 20) {
                        ForEach(containerManager.containers.filter { $0.isEnabled }) { game in
                            GameCardView(game: game)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Game Library")
    }
}

struct GameCardView: View {
    let game: ContainerManager.Container
    var body: some View {
        VStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray4))
                .frame(width: 150, height: 150)
                .overlay(Image(systemName: "gamecontroller").font(.system(size: 40)).foregroundColor(.white))
            Text(game.name).font(.caption).bold().lineLimit(2).multilineTextAlignment(.center)
        }
        .frame(width: 150)
    }
}
