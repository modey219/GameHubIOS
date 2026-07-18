import Foundation

class ContainerManager: ObservableObject {
    @Published var containers: [Container] = []
    @Published var selectedContainer: Container?
    @Published var isLoading = false

    struct Container: Identifiable, Codable {
        var id = UUID()
        var name: String
        var executablePath: String
        var iconPath: String?
        var createdAt: Date
        var lastPlayed: Date?
        var winePrefix: String?
        var environment: [String: String]
        var graphicsConfig: GraphicsConfig
        var inputConfig: InputConfig
        var isEnabled: Bool = true

        struct GraphicsConfig: Codable {
            var renderer: String = "vulkan"
            var useDXVK: Bool = true
            var useVKD3D: Bool = true
            var maxFrameRate: Int = 60
            var vsync: Bool = true
            var resolutionScale: Float = 1.0
            var showFPS: Bool = true
        }

        struct InputConfig: Codable {
            var useVirtualGamepad: Bool = true
            var gamepadType: String = "xbox"
            var sensitivity: Float = 1.0
            var deadzone: Float = 0.15
            var hapticFeedback: Bool = true
        }
    }

    private let containersKey = "GameHubContainers"
    private let fileManager = FileManager.default

    init() {
        loadContainers()
    }

    var containersPath: String {
        return fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Containers").path
    }

    func createContainer(name: String, executablePath: String) -> Container {
        let container = Container(
            name: name,
            executablePath: executablePath,
            createdAt: Date(),
            environment: [:],
            graphicsConfig: Container.GraphicsConfig(),
            inputConfig: Container.InputConfig()
        )

        setupContainerFiles(container: container)
        containers.append(container)
        saveContainers()
        return container
    }

    private func setupContainerFiles(container: Container) {
        let containerDir = containersPath + "/\(container.id.uuidString)"
        let driveC = containerDir + "/drive_c"

        try? fileManager.createDirectory(atPath: driveC, withIntermediateDirectories: true)

        let dirs = [
            "drive_c/windows/system32",
            "drive_c/Program Files",
            "drive_c/Program Files (x86)",
            "drive_c/users",
            "drive_c/games",
        ]

        for dir in dirs {
            try? fileManager.createDirectory(atPath: containerDir + "/" + dir, withIntermediateDirectories: true)
        }

        let dxvkConfig = """
        [dxvk]
        dxvk.numAsyncThreads = 2
        dxvk.numCompilerThreads = 4
        dxvk.enableAsync = true
        dxvk.hud = fps
        dxvk.maxFrameRate = \(container.graphicsConfig.maxFrameRate)
        """
        try? dxvkConfig.write(toFile: containerDir + "/dxvk.conf", atomically: true, encoding: .utf8)

        let wineConfig = """
        [wine]
        UseGLSL = enabled
        CSMT = enabled
        VideoMemorySize = 2048
        OffscreenRenderingMode = fbo
        StrictDrawOrdering = disabled
        MaxFrameLatency = 1
        """
        try? wineConfig.write(toFile: containerDir + "/system.reg", atomically: true, encoding: .utf8)
    }

    func deleteContainer(_ container: Container) {
        let containerDir = containersPath + "/\(container.id.uuidString)"
        try? fileManager.removeItem(atPath: containerDir)

        containers.removeAll { $0.id == container.id }
        if selectedContainer?.id == container.id {
            selectedContainer = nil
        }
        saveContainers()
    }

    func duplicateContainer(_ container: Container, newName: String) -> Container {
        var newContainer = container
        newContainer.id = UUID()
        newContainer.name = newName
        newContainer.createdAt = Date()
        newContainer.lastPlayed = nil

        let srcDir = containersPath + "/\(container.id.uuidString)"
        let dstDir = containersPath + "/\(newContainer.id.uuidString)"

        try? fileManager.copyItem(atPath: srcDir, toPath: dstDir)

        containers.append(newContainer)
        saveContainers()
        return newContainer
    }

    func launchGame(_ container: Container) {
        guard let process = WineBridge.shared.launchGame(
            executablePath: container.executablePath,
            arguments: [],
            containerPath: containersPath + "/\(container.id.uuidString)"
        ) else {
            return
        }

        var updatedContainer = container
        updatedContainer.lastPlayed = Date()
        if let index = containers.firstIndex(where: { $0.id == container.id }) {
            containers[index] = updatedContainer
            saveContainers()
        }

        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.objectWillChange.send()
            }
        }
    }

    func installGameFiles(containerID: UUID, files: [(source: URL, destination: String)]) {
        let containerDir = containersPath + "/\(containerID.uuidString)"

        for file in files {
            let destPath = containerDir + "/" + file.destination
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            try? fileManager.copyItem(atPath: file.source.path, toPath: destPath)
        }
    }

    func getContainerSize(_ container: Container) -> Int64 {
        let containerDir = containersPath + "/\(container.id.uuidString)"
        let url = URL(fileURLWithPath: containerDir)
        return getDirectorySize(url: url)
    }

    private func getDirectorySize(url: URL) -> Int64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else {
            return 0
        }

        var totalSize: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                totalSize += size
            }
        }
        return totalSize
    }

    func getCommonDlls() -> [String] {
        return [
            "d3d11.dll", "d3d10.dll", "d3d9.dll", "d3d8.dll",
            "dxgi.dll", "dinput8.dll", "xinput1_3.dll",
            "msvcrt.dll", "msvcp140.dll", "vcruntime140.dll",
            "ole32.dll", "oleaut32.dll", "shell32.dll",
            "kernel32.dll", "ntdll.dll", "user32.dll",
            "gdi32.dll", "advapi32.dll", "winmm.dll",
        ]
    }

    private func saveContainers() {
        if let data = try? JSONEncoder().encode(containers) {
            UserDefaults.standard.set(data, forKey: containersKey)
        }
    }

    private func loadContainers() {
        guard let data = UserDefaults.standard.data(forKey: containersKey),
              let loaded = try? JSONDecoder().decode([Container].self, from: data) else {
            return
        }
        containers = loaded
    }

    func getInstalledGames() -> [(name: String, path: String, size: Int64)] {
        var games: [(name: String, path: String, size: Int64)] = []

        for container in containers {
            let containerDir = containersPath + "/\(container.id.uuidString)/drive_c"
            let gamesDir = containerDir + "/games"

            if let files = try? fileManager.contentsOfDirectory(atPath: gamesDir) {
                for file in files {
                    let filePath = gamesDir + "/" + file
                    if file.hasSuffix(".exe") {
                        let size = getDirectorySize(url: URL(fileURLWithPath: filePath))
                        games.append((name: (file as NSString).deletingPathExtension, path: filePath, size: size))
                    }
                }
            }
        }

        return games
    }
}
