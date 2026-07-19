import Foundation

class ContainerManager: ObservableObject {
    @Published var containers: [Container] = []
    @Published var selectedContainer: Container?
    @Published var isLoading = false

    private let lock = NSLock()

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

    private let containersKey = "MNEmulatorContainers"
    private let fileManager = FileManager.default

    init() {
        loadContainers()
    }

    var containersPath: String {
        return (fileManager.urls(for: .documentDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory)
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
        lock.lock()
        containers.append(container)
        let snapshot = containers
        lock.unlock()
        saveContainers()
        DispatchQueue.main.async { self.containers = snapshot }
        return container
    }

    private func setupContainerFiles(container: Container) {
        let containerDir = containersPath + "/\(container.id.uuidString)"
        let dirs = ["drive_c", "drive_c/windows/system32", "drive_c/Program Files",
                     "drive_c/Program Files (x86)", "drive_c/users",
                     "drive_c/users/winuser", "drive_c/users/winuser/AppData/Local",
                     "drive_c/users/winuser/AppData/Roaming",
                     "drive_c/users/winuser/Desktop", "drive_c/users/winuser/Documents",
                     "drive_c/games"]
        for dir in dirs {
            try? fileManager.createDirectory(atPath: containerDir + "/" + dir, withIntermediateDirectories: true)
        }

        let systemReg = "Windows Registry Editor Version 5.00\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\Direct3D]\n" +
        "\"UseGLSL\"=\"enabled\"\n" +
        "\"VideoMemorySize\"=\"2048\"\n" +
        "\"CSMT\"=\"enabled\"\n" +
        "\"OffscreenRenderingMode\"=\"fbo\"\n\n" +
        "[HKEY_CURRENT_USER\\Software\\Wine\\DllOverrides]\n" +
        "\"dxgi\"=\"native,builtin\"\n" +
        "\"d3d11\"=\"native,builtin\"\n" +
        "\"d3d9\"=\"native,builtin\"\n"
        try? systemReg.write(toFile: containerDir + "/system.reg", atomically: true, encoding: .utf8)

        let dxvkConfig = "[dxvk]\ndxvk.enableAsync = true\ndxvk.hud = fps\n"
        try? dxvkConfig.write(toFile: containerDir + "/dxvk.conf", atomically: true, encoding: .utf8)
    }

    func deleteContainer(_ container: Container) {
        if Box64Bridge.shared.isRunning {
            Box64Bridge.shared.stopWine()
        }
        try? fileManager.removeItem(atPath: containersPath + "/\(container.id.uuidString)")
        lock.lock()
        containers.removeAll { $0.id == container.id }
        let deselected = selectedContainer?.id == container.id
        let snapshot = containers
        lock.unlock()
        saveContainers()
        DispatchQueue.main.async {
            self.containers = snapshot
            if deselected { self.selectedContainer = nil }
        }
    }

    func launchGame(_ container: Container) {
        guard !container.executablePath.isEmpty else { return }
        var updated = container
        updated.lastPlayed = Date()
        lock.lock()
        if let idx = containers.firstIndex(where: { $0.id == container.id }) {
            containers[idx] = updated
        }
        let snapshot = containers
        lock.unlock()
        saveContainers()
        DispatchQueue.main.async { self.containers = snapshot }
    }

    func installGameFiles(containerID: UUID, files: [(source: URL, destination: String)]) {
        let containerDir = containersPath + "/\(containerID.uuidString)"
        let gamesDir = containerDir + "/drive_c/games"
        try? fileManager.createDirectory(atPath: gamesDir, withIntermediateDirectories: true)
        for file in files {
            let destPath = containerDir + "/" + file.destination
            let destDir = (destPath as NSString).deletingLastPathComponent
            try? fileManager.createDirectory(atPath: destDir, withIntermediateDirectories: true)
            try? fileManager.copyItem(atPath: file.source.path, toPath: destPath)
        }
    }

    func getContainerSize(_ container: Container) -> Int64 {
        let url = URL(fileURLWithPath: containersPath + "/\(container.id.uuidString)")
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? fileManager.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 { total += size }
        }
        return total
    }

    func duplicateContainer(_ container: Container, newName: String) -> Container {
        var newContainer = container
        newContainer.id = UUID()
        newContainer.name = newName
        newContainer.createdAt = Date()
        newContainer.lastPlayed = nil
        try? fileManager.copyItem(
            atPath: containersPath + "/\(container.id.uuidString)",
            toPath: containersPath + "/\(newContainer.id.uuidString)"
        )
        lock.lock()
        containers.append(newContainer)
        lock.unlock()
        saveContainers()
        return newContainer
    }

    private func saveContainers() {
        lock.lock()
        let snapshot = containers
        lock.unlock()
        if let data = try? JSONEncoder().encode(snapshot) {
            UserDefaults.standard.set(data, forKey: containersKey)
        }
    }

    private func loadContainers() {
        guard let data = UserDefaults.standard.data(forKey: containersKey),
              let loaded = try? JSONDecoder().decode([Container].self, from: data) else { return }
        lock.lock()
        containers = loaded
        lock.unlock()
    }
}
