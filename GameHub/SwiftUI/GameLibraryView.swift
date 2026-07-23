import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @State private var showAddGame = false

    var body: some View {
        NavigationStack {
            ZStack {
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

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showAddGame = true }) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 56))
                                .foregroundColor(.blue)
                                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 20)
                    }
                }
            }
            .navigationTitle("Game Library")
            .sheet(isPresented: $showAddGame) { AddGameView() }
        }
    }
}

struct GameCardView: View {
    let game: ContainerManager.Container
    var body: some View {
        VStack(spacing: 8) {
            if let iconPath = game.iconPath, let uiImage = UIImage(contentsOfFile: iconPath) {
                Image(uiImage: uiImage).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150).cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray4))
                    .frame(width: 150, height: 150)
                    .overlay(Image(systemName: "gamecontroller").font(.system(size: 40)).foregroundColor(.white))
            }
            Text(game.name).font(.caption).bold().lineLimit(2).multilineTextAlignment(.center)
            if let lastPlayed = game.lastPlayed {
                Text(lastPlayed, style: .relative).font(.caption2).foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
    }
}
