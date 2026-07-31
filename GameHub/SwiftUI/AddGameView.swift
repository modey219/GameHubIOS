import SwiftUI

struct AddGameView: View {
    let containerManager: ContainerManager
    let onDismiss: () -> Void
    @State private var gameName = ""
    @State private var executablePath = ""
    @State private var selectedFiles: [URL] = []
    @State private var isImporting = false
    @State private var isInstalling = false
    @State private var errorMessage: String?
    @State private var showDocBrowser = false
    @State private var docItems: [URL] = []

    private var safeFolderName: String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
        let cleaned = gameName.components(separatedBy: invalid).joined(separator: "_")
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "game" : trimmed
    }

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
                            executablePath = "C:\\games\\\(safeFolderName)\\\(safeFolderName).exe"
                        }
                    }

                    if isImporting {
                        ProgressView("Importing files...")
                    } else if isInstalling {
                        ProgressView("Installing game...")
                    } else {
                        Button(action: presentFilePicker) {
                            Label("Select Game Files", systemImage: "doc.badge.plus")
                        }
                        Button(action: scanDocuments) {
                            Label("Browse Files in App", systemImage: "folder")
                        }
                        .buttonStyle(.bordered)
                    }

                    if showDocBrowser {
                        if docItems.isEmpty {
                            Text("No game files found. Put your .exe in:\nFiles App → On My iPhone → MN emulator\nThen tap Browse again.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        } else {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Files in app (tap to select):").font(.caption).bold()
                                ForEach(docItems, id: \.self) { item in
                                    Button(action: { selectDocument(item) }) {
                                        HStack {
                                            Image(systemName: item.hasDirectoryPath ? "folder" : "doc")
                                                .foregroundColor(item.hasDirectoryPath ? .orange : .blue)
                                            Text(item.lastPathComponent).font(.caption).lineLimit(1)
                                            Spacer()
                                        }
                                        .padding(.vertical, 4)
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            .padding(8)
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                        }
                    }

                    if !selectedFiles.isEmpty {
                        Text("\(selectedFiles.count) file(s) selected:")
                            .font(.caption).foregroundColor(.secondary)
                        ForEach(selectedFiles, id: \.self) { file in
                            HStack {
                                Image(systemName: "doc")
                                Text(file.lastPathComponent).font(.caption)
                                Spacer()
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundColor(.red)
                            .textSelection(.enabled)
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
    }

    private func presentFilePicker() {
        DocumentPickerPresenter.present(
            types: [.data, .folder],
            allowsMultiple: true,
            onPick: { [self] urls in
                self.handlePickedURLs(urls)
            }
        )
    }

    private func handlePickedURLs(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        isImporting = true
        errorMessage = nil

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            errorMessage = "Cannot access Documents directory"
            isImporting = false
            return
        }

        let stagingBase = docs.appendingPathComponent("Staging")
        try? fm.createDirectory(at: stagingBase, withIntermediateDirectories: true)
        let stagingDir = stagingBase.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: stagingDir, withIntermediateDirectories: true)

        var copied: [URL] = []
        var copyError: String?

        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            let dest = stagingDir.appendingPathComponent(url.lastPathComponent)
            do {
                try fm.copyItem(at: url, to: dest)
                copied.append(dest)
                NSLog("[MNEmulator] staged \(url.lastPathComponent) -> \(dest.path)")
            } catch {
                NSLog("[MNEmulator] copy failed for \(url.lastPathComponent): \(error)")
                copyError = copyError == nil
                    ? "Couldn't copy '\(url.lastPathComponent)': \(error.localizedDescription)"
                    : "\(copyError!)\nCouldn't copy '\(url.lastPathComponent)': \(error.localizedDescription)"
            }
        }

        if let copyError {
            errorMessage = copyError
        }
        selectedFiles = copied
        isImporting = false

        if let first = urls.first, copied.contains(where: { $0.lastPathComponent == first.lastPathComponent }) {
            let name = first.deletingPathExtension().lastPathComponent
            if gameName.isEmpty { gameName = name }
            executablePath = "C:\\games\\\(safeFolderName)\\\(first.lastPathComponent)"
        }
    }

    private func scanDocuments() {
        docItems = DocumentScanner.contents()
        showDocBrowser = true
        errorMessage = nil
    }

    private func selectDocument(_ url: URL) {
        selectedFiles = [url]
        errorMessage = nil
        var name = url.deletingPathExtension().lastPathComponent
        var fileName = url.lastPathComponent
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
           let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path),
           let exe = entries.first(where: { $0.lowercased().hasSuffix(".exe") }) {
            fileName = exe
            name = (exe as NSString).deletingPathExtension
        }
        if gameName.isEmpty { gameName = name }
        executablePath = "C:\\games\\\(safeFolderName)\\\(fileName)"
    }

    private func addGame() {
        guard !selectedFiles.isEmpty else {
            errorMessage = "Select game files first."
            return
        }
        guard !gameName.isEmpty, !executablePath.isEmpty else {
            errorMessage = "Enter a game name and executable path."
            return
        }
        isInstalling = true
        errorMessage = nil

        let container = containerManager.createContainer(name: gameName, executablePath: executablePath)
        let containerID = container.id
        let files = selectedFiles.map {
            (source: $0, destination: "drive_c/games/\(safeFolderName)/\($0.lastPathComponent)")
        }

        DispatchQueue.global(qos: .userInitiated).async {
            containerManager.installGameFiles(containerID: containerID, files: files)
            DispatchQueue.main.async {
                isInstalling = false
                onDismiss()
            }
        }
    }
}
