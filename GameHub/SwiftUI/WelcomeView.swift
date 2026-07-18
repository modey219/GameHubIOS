import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @StateObject private var downloadManager = RuntimeDownloadManager.shared
    @State private var showSetup = false
    @State private var box64Status = CheckStatus.checking
    @State private var wineStatus = CheckStatus.checking
    @State private var metalStatus = CheckStatus.checking
    @State private var jitStatusCheck = CheckStatus.checking
    @State private var isDownloading = false
    @State private var downloadProgress: Double = 0
    @State private var currentDownloadName = ""
    @State private var showAdvancedSetup = false

    enum CheckStatus {
        case checking, ok, missing
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    statusSection
                    if isDownloading {
                        downloadProgressSection
                    }
                    actionButtons
                    componentListSection
                    infoSection
                }
                .padding()
            }
            .navigationTitle("GameHub")
            .onAppear { checkBinaries() }
        }
    }

    private var headerSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 70))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("GameHub iOS")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                Label("Box64", systemImage: "cpu")
                Text("+")
                Label("Wine", systemImage: "desktopcomputer")
                Text("+")
                Label("MoltenVK", systemImage: "paintbrush")
            }
            .font(.caption)
            .foregroundColor(.blue)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(8)
        }
        .padding(.top, 10)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)

            statusRow("Box64 (x86_64 translator)", status: box64Status, detail: "Translates x86_64 Linux binaries to ARM64")
            statusRow("Wine (Windows API)", status: wineStatus, detail: "Runs Windows applications")
            statusRow("Metal (GPU)", status: metalStatus, detail: "Apple Metal graphics API")
            statusRow("JIT (Performance)", status: jitStatusCheck, detail: "Just-In-Time compilation")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func statusRow(_ name: String, status: CheckStatus, detail: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Circle()
                    .fill(statusColor(status))
                    .frame(width: 10, height: 10)

                Text(name)
                    .font(.subheadline)

                Spacer()

                switch status {
                case .checking:
                    ProgressView()
                        .scaleEffect(0.7)
                case .ok:
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                case .missing:
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }

            if let detail = detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.leading, 18)
            }
        }
    }

    private func statusColor(_ status: CheckStatus) -> Color {
        switch status {
        case .checking: return .yellow
        case .ok: return .green
        case .missing: return .red
        }
    }

    private var downloadProgressSection: some View {
        VStack(spacing: 12) {
            HStack {
                ProgressView()
                    .scaleEffect(0.8)
                Text("Downloading: \(currentDownloadName)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text("\(Int(downloadProgress * 100))%")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            ProgressView(value: downloadProgress)
                .progressViewStyle(LinearProgressViewStyle())

            if let msg = RuntimeDownloadManager.shared.statusMessage.isEmpty ? nil : RuntimeDownloadManager.shared.statusMessage {
                Text(msg)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if box64Status == .missing || wineStatus == .missing {
                Button(action: downloadAllComponents) {
                    Label("Download All Components", systemImage: "icloud.and.arrow.down")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(isDownloading ? Color.gray : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .disabled(isDownloading)

                Button(action: { showAdvancedSetup = true }) {
                    Label("Advanced Setup", systemImage: "wrench.and.screwdriver")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            } else if jitStatusCheck == .missing {
                Button(action: {}) {
                    Label("Enable JIT (StikDebug)", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.yellow)
                        .foregroundColor(.black)
                        .cornerRadius(12)
                }

                NavigationLink(destination: GameLibraryView()) {
                    Label("Continue Without JIT", systemImage: "gamecontroller")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            } else {
                NavigationLink(destination: GameLibraryView()) {
                    Label("Start Playing", systemImage: "gamecontroller.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var componentListSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Components")
                .font(.headline)

            ForEach(downloadManager.getComponents()) { component in
                componentRow(component)
            }

            HStack {
                Text("Total Download:")
                    .font(.caption)
                Spacer()
                Text(formatBytes(downloadManager.getTotalDownloadSize()))
                    .font(.caption)
                    .foregroundColor(.blue)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func componentRow(_ component: RuntimeDownloadManager.ComponentInfo) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(component.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("v\(component.version) • \(formatBytes(component.sizeBytes))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if downloadManager.isComponentInstalled(component.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if isDownloading {
                if case .downloading(let progress) = downloadManager.getComponentStatus(component.id) {
                    ProgressView(value: progress)
                        .frame(width: 60)
                } else if case .extracting = downloadManager.getComponentStatus(component.id) {
                    ProgressView()
                        .scaleEffect(0.7)
                } else {
                    Button("Get") {
                        downloadComponent(component)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            } else {
                Button("Get") {
                    downloadComponent(component)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)

            infoRow(icon: "cpu", title: "Box64", desc: "Translates x86_64 Linux binaries to ARM64 in real-time")
            infoRow(icon: "desktopcomputer", title: "Wine", desc: "Implements Windows API on iOS")
            infoRow(icon: "paintbrush", title: "MoltenVK", desc: "Translates Vulkan API to Apple Metal")
            infoRow(icon: "gamecontroller", title: "DXVK", desc: "Translates DirectX 11 to Vulkan for better performance")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func infoRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func checkBinaries() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        box64Status = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path) ? .ok : .missing
        wineStatus = fm.fileExists(atPath: docs.appendingPathComponent("Wine/wine64").path) ? .ok : .missing
        metalStatus = MTLCreateSystemDefaultDevice() != nil ? .ok : .missing
        jitStatusCheck = jitManager.isJITEnabled ? .ok : .missing
    }

    private func downloadAllComponents() {
        isDownloading = true
        downloadProgress = 0

        let required = downloadManager.getComponents().filter { $0.isRequired && !downloadManager.isComponentInstalled($0.id) }

        guard !required.isEmpty else {
            isDownloading = false
            checkBinaries()
            return
        }

        var completedCount = 0
        let totalCount = required.count

        for component in required {
            currentDownloadName = component.name

            downloadManager.downloadComponent(component)

            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
                if self.downloadManager.isComponentInstalled(component.id) {
                    timer.invalidate()
                    completedCount += 1
                    self.downloadProgress = Double(completedCount) / Double(totalCount)

                    if completedCount >= totalCount {
                        self.isDownloading = false
                        self.checkBinaries()
                        self.downloadManager.setupEnvironment()
                    }
                }
            }
        }
    }

    private func downloadComponent(_ component: RuntimeDownloadManager.ComponentInfo) {
        currentDownloadName = component.name
        downloadManager.downloadComponent(component)
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

struct AdvancedSetupView: View {
    @State private var showFilePicker = false
    @State private var binaryPath = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Manual Binary Installation")
                    .font(.title3)
                    .fontWeight(.bold)

                Text("If automatic download doesn't work, you can manually place binaries:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                methodCard(
                    num: 1,
                    title: "Transfer via iTunes/Finder",
                    body: """
                    1. Connect iPhone to Mac/PC
                    2. Open Finder (macOS) or iTunes (Windows)
                    3. Select iPhone → File Sharing → GameHub
                    4. Drag and drop the binaries
                    """
                )

                methodCard(
                    num: 2,
                    title: "Transfer via WebDAV",
                    body: """
                    1. Use a WebDAV client ( Cyberduck, WinSCP)
                    2. Connect to your iPhone
                    3. Navigate to GameHub's Documents folder
                    4. Upload binaries to Box64/ and Wine/ folders
                    """
                )

                methodCard(
                    num: 3,
                    title: "Transfer via iCloud Drive",
                    body: """
                    1. Copy binaries to iCloud Drive
                    2. Open Files app on iPhone
                    3. Move binaries to GameHub folder
                    """
                )

                VStack(alignment: .leading, spacing: 8) {
                    Text("Required Files")
                        .font(.headline)

                    fileLocation("box64", path: "Documents/Box64/box64")
                    fileLocation("wine64", path: "Documents/Wine/wine64")
                    fileLocation("wineserver", path: "Documents/Wine/wineserver")
                    fileLocation("rootfs (optional)", path: "Documents/Wine/rootfs/")
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Advanced Setup")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func methodCard(num: Int, title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ZStack {
                    Circle().fill(Color.blue).frame(width: 28, height: 28)
                    Text("\(num)").font(.caption).fontWeight(.bold).foregroundColor(.white)
                }
                Text(title).font(.headline)
            }
            Text(body)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func fileLocation(_ name: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).fontWeight(.medium)
            Text(path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
        }
    }
}
