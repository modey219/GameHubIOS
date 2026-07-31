import SwiftUI
import UniformTypeIdentifiers

struct AddGameView: View {
    let containerManager: ContainerManager
    let onDismiss: () -> Void
    @State private var gameName = ""
    @State private var executablePath = ""
    @State private var showFilePicker = false
    @State private var selectedFiles: [URL] = []
    @State private var isImporting = false
    @State private var isInstalling = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Cancel") { onDismiss() }
                    .padding(.leading)
                Spacer()
                Text("Add Game").font(.headline).foregroundColor(.primary)
                Spacer()
                Button("Add") { addGame() }
                    .disabled(gameName.isEmpty || executablePath.isEmpty || isInstalling)
                    .padding(.trailing)
            }
            .padding(.vertical)
            .background(Color.gray.opacity(0.2))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text("Game Name").font(.subheadline).bold()
                        TextField("Game Name", text: $gameName)
                            .textFieldStyle(.roundedBorder)
                    }

                    Group {
                        Text("Executable Path (.exe)").font(.subheadline).bold()
                        TextField("Executable Path (.exe)", text: $executablePath)
                            .textFieldStyle(.roundedBorder)
                            .autocapitalization(.none)
                            .textInputAutocapitalization(.never)
                    }

                    if executablePath.isEmpty && !gameName.isEmpty {
                        Button("Auto-fill path") {
                            executablePath = "C:\\games\\\(gameName)\\\(gameName).exe"
                        }
                    }

                    if isImporting {
                        ProgressView("Importing files...")
                    } else if isInstalling {
                        ProgressView("Installing game...")
                    } else {
                        Button(action: { showFilePicker = true }) {
                            Label("Select Game Files", systemImage: "doc.badge.plus")
                        }
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

                    Button(action: addGame) {
                        Text("Add Game").fontWeight(.bold).frame(maxWidth: .infinity)
                    }
                    .disabled(gameName.isEmpty || executablePath.isEmpty || isInstalling)
                    .buttonStyle(.borderedProminent)
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .fileImporter(isPresented: $showFilePicker, allowedContentTypes: [.data, .folder], allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                isImporting = true
                let fm = FileManager.default
                let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
                for url in urls { _ = url.startAccessingSecurityScopedResource() }
                DispatchQueue.global(qos: .userInitiated).async {
                    var copiedURLs: [URL] = []
                    for url in urls {
                        let dest = tempDir.appendingPathComponent(url.lastPathComponent)
                        if (try? fm.copyItem(at: url, to: dest)) != nil {
                            copiedURLs.append(dest)
                        }
                    }
                    DispatchQueue.main.async {
                        for url in urls { url.stopAccessingSecurityScopedResource() }
                        selectedFiles = copiedURLs
                        isImporting = false
                        if let first = urls.first {
                            let name = first.deletingPathExtension().lastPathComponent
                            if gameName.isEmpty { gameName = name }
                            executablePath = "C:\\games\\\(gameName)\\\(first.lastPathComponent)"
                        }
                    }
                }
            }
        }
    }

    private func addGame() {
        let container = containerManager.createContainer(name: gameName, executablePath: executablePath)
        guard !selectedFiles.isEmpty else { onDismiss(); return }
        isInstalling = true
        let files = selectedFiles.map { (source: $0, destination: "drive_c/games/\(gameName)/\($0.lastPathComponent)" ) }
        let containerID = container.id
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.containerManager.installGameFiles(containerID: containerID, files: files)
            DispatchQueue.main.async {
                self?.isInstalling = false
                self?.onDismiss()
            }
        }
    }
}
