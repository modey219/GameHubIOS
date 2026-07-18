import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @State private var searchText = ""
    @State private var showAddGame = false
    @State private var showImportSheet = false
    @State private var selectedGame: ContainerManager.Container?

    var filteredGames: [ContainerManager.Container] {
        if searchText.isEmpty {
            return containerManager.containers.filter { $0.isEnabled }
        }
        return containerManager.containers.filter {
            $0.isEnabled && $0.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            Group {
                if filteredGames.isEmpty {
                    emptyStateView
                } else {
                    gameListView
                }
            }
            .navigationTitle("Game Library")
            .searchable(text: $searchText, prompt: "Search games...")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showImportSheet = true }) {
                        Image(systemName: "square.and.arrow.down")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddGame = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddGame) {
                AddGameView()
            }
            .sheet(isPresented: $showImportSheet) {
                ImportGameView()
            }
            .fullScreenCover(item: $selectedGame) { game in
                GameContainerView(container: game)
            }
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text("No Games Yet")
                .font(.title2)
                .fontWeight(.bold)
            Text("Import or add PC games to start playing")
                .foregroundColor(.secondary)
            Button(action: { showAddGame = true }) {
                Label("Add Game", systemImage: "plus")
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
        }
    }

    private var gameListView: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)
            ], spacing: 20) {
                ForEach(filteredGames) { game in
                    GameCardView(game: game)
                        .onTapGesture {
                            selectedGame = game
                        }
                        .contextMenu {
                            Button(action: { launchGame(game) }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button(action: { showGameSettings(game) }) {
                                Label("Settings", systemImage: "gear")
                            }
                            Button(action: { deleteGame(game) }, role: .destructive) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
        }
    }

    private func launchGame(_ game: ContainerManager.Container) {
        containerManager.launchGame(game)
    }

    private func showGameSettings(_ game: ContainerManager.Container) {
        selectedGame = game
    }

    private func deleteGame(_ game: ContainerManager.Container) {
        containerManager.deleteContainer(game)
    }
}

struct GameCardView: View {
    let game: ContainerManager.Container

    var body: some View {
        VStack(spacing: 8) {
            if let iconPath = game.iconPath, let uiImage = UIImage(contentsOfFile: iconPath) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 150, height: 150)
                    .cornerRadius(12)
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 150, height: 150)
                    .overlay(
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 40))
                            .foregroundColor(.white)
                    )
            }

            Text(game.name)
                .font(.caption)
                .fontWeight(.medium)
                .lineLimit(2)
                .multilineTextAlignment(.center)

            if let lastPlayed = game.lastPlayed {
                Text(lastPlayed, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 150)
    }
}
