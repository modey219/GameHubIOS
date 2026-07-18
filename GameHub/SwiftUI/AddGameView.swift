import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @Environment(\.dismiss) var dismiss
    @State private var gameName = ""
    @State private var executablePath = ""
    @State private var showFilePicker = false
    @State private var selectedFiles: [URL] = []
    @State private var isImporting = false

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Game Info")) {
                    TextField("Game Name", text: $gameName)
                    TextField("Executable Path (.exe)", text: $executablePath)
                        .autocapitalization(.none)
                }

                Section(header: Text("Import Files")) {
                    Button(action: { showFilePicker = true }) {
                        Label("Select Game Files", systemImage: "doc.badge.plus")
                    }

                    if !selectedFiles.isEmpty {
                        ForEach(selectedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent)
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section(header: Text("Quick Setup")) {
                    Button(action: importFromDocuments) {
                        Label("Import from Files App", systemImage: "folder")
                    }

                    Button(action: importFromDownloads) {
                        Label("Import from Downloads", systemImage: "arrow.down.circle")
                    }

                    Button(action: importFromClipboard) {
                        Label("Import Path from Clipboard", systemImage: "doc.on.clipboard")
                    }
                }

                Section {
                    Button(action: addGame) {
                        HStack {
                            if isImporting {
                                ProgressView()
                                    .padding(.trailing, 8)
                            }
                            Text(isImporting ? "Adding Game..." : "Add Game")
                                .fontWeight(.bold)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .disabled(gameName.isEmpty || executablePath.isEmpty || isImporting)
                }
            }
            .navigationTitle("Add Game")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.data, .folder, .item],
                allowsMultipleSelection: true
            ) { result in
                handleFileImport(result)
            }
        }
    }

    private func addGame() {
        isImporting = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let container = containerManager.createContainer(
                name: gameName,
                executablePath: executablePath
            )

            if !selectedFiles.isEmpty {
                let files = selectedFiles.map { (source: $0, destination: $0.lastPathComponent) }
                containerManager.installGameFiles(containerID: container.id, files: files)
            }

            isImporting = false
            dismiss()
        }
    }

    private func importFromDocuments() {
        showFilePicker = true
    }

    private func importFromDownloads() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let downloadsPath = documentsPath.appendingPathComponent("Downloads")

        if let files = try? FileManager.default.contentsOfDirectory(at: downloadsPath, includingPropertiesForKeys: nil) {
            selectedFiles = files.filter { $0.pathExtension.lowercased() == "exe" }
            if let firstExe = selectedFiles.first {
                executablePath = "C:\\games\\\(firstExe.lastPathComponent)"
                if gameName.isEmpty {
                    gameName = firstExe.deletingPathExtension().lastPathComponent
                }
            }
        }
    }

    private func importFromClipboard() {
        if let pasteboardString = UIPasteboard.general.string {
            executablePath = pasteboardString
            if gameName.isEmpty {
                gameName = URL(fileURLWithPath: pasteboardString).deletingPathExtension().lastPathComponent
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            selectedFiles = urls
            if let firstExe = urls.first(where: { $0.pathExtension.lowercased() == "exe" }) {
                executablePath = "C:\\games\\\(firstExe.lastPathComponent)"
                if gameName.isEmpty {
                    gameName = firstExe.deletingPathExtension().lastPathComponent
                }
            }
        case .failure(let error):
            print("File import failed: \(error)")
        }
    }
}
