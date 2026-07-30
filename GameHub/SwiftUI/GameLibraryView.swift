import SwiftUI

enum SheetContent: Identifiable {
    case addGame
    case gameContainer(ContainerManager.Container)

    var id: String {
        switch self {
        case .addGame: return "addGame"
        case .gameContainer(let game): return game.id.uuidString
        }
    }
}

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showImportSheet = false
    @State private var activeSheet: SheetContent?

    var filteredGames: [ContainerManager.Container] {
        if searchText.isEmpty { return containerManager.containers.filter { $0.isEnabled } }
        return containerManager.containers.filter { $0.isEnabled && $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if showSearch {
                searchField
            }
            if filteredGames.isEmpty {
                emptyState
            } else {
                gameGrid
            }
        }
        .sheet(item: $activeSheet) { content in
            switch content {
            case .addGame:
                AddGameView()
                    .environmentObject(containerManager)
            case .gameContainer(let game):
                GameContainerView(container: game)
            }
        }
        .fullScreenCover(isPresented: $showImportSheet) {
            ImportGameView()
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: { showImportSheet = true }) {
                Label("Import", systemImage: "square.and.arrow.down")
            }
            Spacer()
            Text("Game Library").font(.headline)
            Spacer()
            HStack(spacing: 20) {
                Button(action: { withAnimation { showSearch.toggle() } }) {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: { activeSheet = .addGame }) {
                    Image(systemName: "plus")
                }
            }
        }
        .padding()
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundColor(.secondary)
            TextField("Search games...", text: $searchText)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller")
                .font(.system(size: 60)).foregroundColor(.gray)
            Text("No Games Yet").font(.title2).bold()
            Text("Import or add PC games to start playing").foregroundColor(.secondary)
            Button(action: { activeSheet = .addGame }) {
                Label("Add Game", systemImage: "plus")
                    .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }
        }
    }

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 20) {
                ForEach(filteredGames) { game in
                    GameCardView(game: game)
                        .onTapGesture { activeSheet = .gameContainer(game) }
                        .contextMenu {
                            Button(action: { activeSheet = .gameContainer(game) }) {
                                Label("Play", systemImage: "play.fill")
                            }
                            Button(role: .destructive, action: { containerManager.deleteContainer(game) }) {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
            .padding()
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
