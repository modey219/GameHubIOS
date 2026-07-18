import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @Environment(\.dismiss) var dismiss
    @State private var gameName = ""
    @State private var executablePath = ""
    @State private var showFilePicker = false
    @State private var selectedFiles: [URL] = []

    var body: some View {
        NavigationView {
            Form {
                Section("Game Info") {
                    TextField("Game Name", text: $gameName)
                    TextField("Executable Path (.exe)", text: $executablePath)
                        .autocapitalization(.none)
                        .textInputAutocapitalization(.never)
                    if executablePath.isEmpty && !gameName.isEmpty {
                        Button("Auto-fill path") {
                            executablePath = "C:\\games\\\(gameName)\\\(gameName).exe"
                        }
                    }
                }
                Section("Import Files") {
                    Button(action: { showFilePicker = true }) {
                        Label("Select Game Files", systemImage: "doc.badge.plus")
                    }
                    if !selectedFiles.isEmpty {
                        ForEach(selectedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent).font(.caption)
                                Spacer()
                            }
                        }
                    }
                }
                Section {
                    Button(action: addGame) {
                        Text("Add Game").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .disabled(gameName.isEmpty || executablePath.isEmpty)
                }
            }
            .navigationTitle("Add Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) { Button("Cancel") { dismiss() } }
            }
            .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
                if case .success(let urls) = result {
                    selectedFiles = urls
                    if let first = urls.first {
                        executablePath = "C:\\games\\\(first.deletingPathExtension().lastPathComponent)\\\(first.lastPathComponent)"
                        if gameName.isEmpty { gameName = first.deletingPathExtension().lastPathComponent }
                    }
                }
            }
        }
    }

    private func addGame() {
        let container = containerManager.createContainer(name: gameName, executablePath: executablePath)
        if !selectedFiles.isEmpty {
            let files = selectedFiles.map { (source: $0, destination: "drive_c/games/\(gameName)/\($0.lastPathComponent)" ) }
            containerManager.installGameFiles(containerID: container.id, files: files)
        }
        dismiss()
    }
}
