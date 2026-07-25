import SwiftUI

struct GameLibraryView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @State private var searchText = ""
    @State private var showSearch = false
    @State private var showAddGame = false
    @State private var showImportSheet = false
    @State private var selectedGame: ContainerManager.Container?

    var filteredGames: [ContainerManager.Container] {
        if searchText.isEmpty { return containerManager.containers.filter { $0.isEnabled } }
        return containerManager.containers.filter { $0.isEnabled && $0.name.localizedCaseInsensitiveContains(searchText) }
    }

    // NOTE: intentionally NOT using NavigationStack/.searchable/.toolbar here.
    // On some iOS versions (observed on iOS 27 beta) SwiftUI's NavigationStack
    // relies on UINavigationController-backed layout that can enter a
    // pathological/looping layout pass on first render, tripping the
    // "scene-create" watchdog (0x8BADF00D) and getting the app killed before
    // it ever appears (same underlying class of bug reported for TabView on
    // recent iOS betas: dotnet/maui#32365). Using a plain manual layout
    // avoids that code path entirely.
    // DIAGNOSTIC stage 3: stage 2 (removing the games if/else + ForEach) did
    // NOT fix the scene-create watchdog crash - the exact same
    // DynamicViewList/DynamicContainerInfo stack trace appeared again. That
    // means the "if filteredGames.isEmpty" conditional wasn't the (only)
    // trigger - other dynamic-content constructs remained: `if showSearch {...}`
    // and 3 presentation modifiers (.sheet x2, .fullScreenCover) which are
    // ALSO inherently "dynamic view" constructs in SwiftUI (they need to
    // decide whether to host their content based on a binding). This stage
    // removes ALL of them, leaving only topBar + emptyState (no conditionals,
    // no sheets, no fullScreenCover) to see if that's enough to avoid the
    // watchdog entirely.
    var body: some View {
        VStack(spacing: 0) {
            topBar
            emptyState
        }
    }

    // DIAGNOSTIC stage 4: stage 3 (topBar + emptyState only, zero
    // conditionals, zero sheets) STILL hit the exact same scene-create
    // watchdog. The only other thing distinguishing this from the
    // known-good bare Text() test is the SF Symbols (Image(systemName:)) -
    // topBar had 3, emptyState had 1. SF Symbol resolution goes through a
    // large system font/catalog lookup that could plausibly be broken or
    // pathologically slow on a pre-release iOS beta. This stage replaces
    // every Image(systemName:) with plain Text glyphs to isolate that.
    private var topBar: some View {
        HStack {
            Button(action: { showImportSheet = true }) {
                Text("Import")
            }
            Spacer()
            Text("Game Library").font(.headline)
            Spacer()
            HStack(spacing: 20) {
                Button(action: { withAnimation { showSearch.toggle() } }) {
                    Text("Search")
                }
                Button(action: { showAddGame = true }) {
                    Text("+")
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
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.gray)
                .frame(width: 60, height: 60)
            Text("No Games Yet").font(.title2).bold()
            Text("Import or add PC games to start playing").foregroundColor(.secondary)
            Button(action: { showAddGame = true }) {
                Text("Add Game")
                    .padding().background(Color.blue).foregroundColor(.white).cornerRadius(10)
            }
        }
    }

    private var gameGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150, maximum: 200), spacing: 20)], spacing: 20) {
                ForEach(filteredGames) { game in
                    GameCardView(game: game)
                        .onTapGesture { selectedGame = game }
                        .contextMenu {
                            Button(action: { selectedGame = game }) {
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
