import Foundation
import Combine

class RuntimeDownloadManager: ObservableObject {
    static let shared = RuntimeDownloadManager()

    @Published var downloadProgress: [String: Double] = [:]
    @Published var downloadStatus: [String: DownloadState] = [:]
    @Published var overallStatus: OverallStatus = .idle
    @Published var errorMessage: String?
    @Published var statusMessage: String = ""

    enum DownloadState: Equatable {
        case idle
        case downloading(progress: Double)
        case extracting
        case completed
        case failed(String)
        case waiting
    }

    enum OverallStatus: String {
        case idle = "Ready"
        case downloadingComponents = "Downloading components..."
        case extractingArchives = "Extracting archives..."
        case settingUpEnvironment = "Setting up environment..."
        case ready = "Ready to play"
        case error = "Error occurred"
    }

    struct ComponentInfo: Identifiable {
        let id: String
        let name: String
        let fileName: String
        let url: String
        let sizeBytes: Int64
        let extractTo: String
        let isRequired: Bool
        let version: String
    }

    private let baseDownloadURL = "https://github.com/modey219/GameHubIOS/releases/download"
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

    private var components: [ComponentInfo] {
        let box64Version = "0.4.0"
        let wineVersion = "9.0"
        let mvkVersion = "1.2.5"
        let dxvkVersion = "2.4.1"

        return [
            ComponentInfo(
                id: "box64",
                name: "Box64 (x86_64 Translator)",
                fileName: "box64-\(box64Version)-ios-arm64.tzst",
                url: "\(baseDownloadURL)/binaries/box64-\(box64Version)-ios-arm64.tzst",
                sizeBytes: 2_500_000,
                extractTo: "Box64",
                isRequired: true,
                version: box64Version
            ),
            ComponentInfo(
                id: "wine",
                name: "Wine \(wineVersion) (Windows API)",
                fileName: "wine-\(wineVersion)-ios-arm64.tzst",
                url: "\(baseDownloadURL)/binaries/wine-\(wineVersion)-ios-arm64.tzst",
                sizeBytes: 85_000_000,
                extractTo: "Wine",
                isRequired: true,
                version: wineVersion
            ),
            ComponentInfo(
                id: "rootfs",
                name: "Root Filesystem",
                fileName: "rootfs-ios-arm64.tzst",
                url: "\(baseDownloadURL)/binaries/rootfs-ios-arm64.tzst",
                sizeBytes: 150_000_000,
                extractTo: "Wine/rootfs",
                isRequired: true,
                version: "1.0"
            ),
            ComponentInfo(
                id: "moltenvk",
                name: "MoltenVK \(mvkVersion) (Vulkan → Metal)",
                fileName: "moltenvk-\(mvkVersion)-ios-arm64.tzst",
                url: "\(baseDownloadURL)/binaries/moltenvk-\(mvkVersion)-ios-arm64.tzst",
                sizeBytes: 8_000_000,
                extractTo: "Graphics/MoltenVK",
                isRequired: false,
                version: mvkVersion
            ),
            ComponentInfo(
                id: "dxvk",
                name: "DXVK \(dxvkVersion) (DX11 → Vulkan)",
                fileName: "dxvk-\(dxvkVersion)-ios-arm64.tzst",
                url: "\(baseDownloadURL)/binaries/dxvk-\(dxvkVersion)-ios-arm64.tzst",
                sizeBytes: 5_000_000,
                extractTo: "Graphics/DXVK",
                isRequired: false,
                version: dxvkVersion
            ),
        ]
    }

    func getComponents() -> [ComponentInfo] { components }

    func getComponentStatus(_ id: String) -> DownloadState {
        return downloadStatus[id] ?? .idle
    }

    func isComponentInstalled(_ id: String) -> Bool {
        guard let component = components.first(where: { $0.id == id }) else { return false }
        let destPath = documentsPath.appendingPathComponent(component.extractTo)
        return FileManager.default.fileExists(atPath: destPath.path)
    }

    func isAllRequiredInstalled() -> Bool {
        components.filter { $0.isRequired }.allSatisfy { isComponentInstalled($0.id) }
    }

    func downloadComponent(_ component: ComponentInfo) {
        guard !isComponentInstalled(component.id) else {
            downloadStatus[component.id] = .completed
            return
        }

        downloadStatus[component.id] = .downloading(progress: 0)
        overallStatus = .downloadingComponents

        guard let url = URL(string: component.url) else {
            downloadStatus[component.id] = .failed("Invalid URL")
            return
        }

        let task = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.downloadStatus[component.id] = .failed(error.localizedDescription)
                    self.errorMessage = "Failed to download \(component.name): \(error.localizedDescription)"
                }
                return
            }

            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    self.downloadStatus[component.id] = .failed("No data received")
                }
                return
            }

            DispatchQueue.main.async {
                self.downloadStatus[component.id] = .extracting
                self.statusMessage = "Extracting \(component.name)..."
            }

            self.extractComponent(component: component, from: tempURL)

            DispatchQueue.main.async {
                self.downloadStatus[component.id] = .completed
                self.statusMessage = "\(component.name) installed!"

                if self.isAllRequiredInstalled() {
                    self.overallStatus = .ready
                    self.setupEnvironment()
                }
            }
        }

        task.resume()
    }

    func downloadAllRequired() {
        overallStatus = .downloadingComponents
        let required = components.filter { $0.isRequired }

        for component in required {
            if !isComponentInstalled(component.id) {
                downloadComponent(component)
            }
        }
    }

    private func extractComponent(component: ComponentInfo, from tempURL: URL) {
        let fm = FileManager.default
        let destDir = documentsPath.appendingPathComponent(component.extractTo)

        if !fm.fileExists(atPath: destDir.path) {
            try? fm.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        let tempDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? fm.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let tempFile = tempDir.appendingPathComponent(component.fileName)
        try? fm.moveItem(at: tempURL, to: tempFile)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["--zstd", "-xf", tempFile.path, "-C", destDir.path]
        try? process.run()
        process.waitUntilExit()

        if component.id == "box64" || component.id == "wine" {
            let binaries: [String]
            if component.id == "box64" {
                binaries = ["box64"]
            } else {
                binaries = ["wine64", "wineserver"]
            }

            for binary in binaries {
                let binaryPath = destDir.appendingPathComponent(binary)
                if fm.fileExists(atPath: binaryPath.path) {
                    try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: binaryPath.path)
                }
            }
        }

        try? fm.removeItem(at: tempDir)
    }

    private func setupEnvironment() {
        overallStatus = .settingUpEnvironment
        statusMessage = "Configuring environment..."

        WinePrefixManager.shared.initializePrefix()
        GraphicsBridge.shared.initialize()

        overallStatus = .ready
        statusMessage = "Ready to play!"
    }

    func deleteComponent(_ id: String) {
        guard let component = components.first(where: { $0.id == id }) else { return }
        let path = documentsPath.appendingPathComponent(component.extractTo)
        try? FileManager.default.removeItem(at: path)
        downloadStatus[id] = .idle
    }

    func getTotalDownloadSize() -> Int64 {
        return components.filter { $0.isRequired && !isComponentInstalled($0.id) }
            .reduce(0) { $0 + $1.sizeBytes }
    }

    func getInstalledSize() -> Int64 {
        var total: Int64 = 0
        for component in components where isComponentInstalled(component.id) {
            let path = documentsPath.appendingPathComponent(component.extractTo)
            total += Self.getDirectorySize(path)
        }
        return total
    }

    private static func getDirectorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }
}
