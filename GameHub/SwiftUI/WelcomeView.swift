import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @State private var showSetup = false
    @State private var box64Status = CheckStatus.checking
    @State private var wineStatus = CheckStatus.checking
    @State private var metalStatus = CheckStatus.checking
    @State private var jitStatusCheck = CheckStatus.checking

    enum CheckStatus {
        case checking, ok, missing
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    headerSection
                    statusSection
                    actionButtons
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
                .font(.system(size: 80))
                .foregroundStyle(
                    LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            Text("GameHub iOS")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline)
                .foregroundColor(.secondary)

            Text("Box64 + Wine + MoltenVK + DXVK")
                .font(.caption)
                .foregroundColor(.blue)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
        }
        .padding(.top, 20)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Check")
                .font(.headline)

            statusRow("Box64 (x86_64 translator)", status: box64Status)
            statusRow("Wine (Windows API)", status: wineStatus)
            statusRow("Metal (GPU)", status: metalStatus)
            statusRow("JIT (Performance)", status: jitStatusCheck)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func statusRow(_ name: String, status: CheckStatus) -> some View {
        HStack {
            Circle()
                .fill(status == .ok ? Color.green : status == .missing ? Color.red : Color.yellow)
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
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            if box64Status == .missing || wineStatus == .missing {
                NavigationLink(destination: SetupGuideView()) {
                    Label("Setup Guide", systemImage: "book.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: openFilesApp) {
                    Label("Import Binaries via Files App", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            } else {
                NavigationLink(destination: GameLibraryView()) {
                    Label("Browse Games", systemImage: "gamecontroller")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)

            infoRow(icon: "cpu", title: "Box64", desc: "Translates x86_64 Linux binaries to ARM64")
            infoRow(icon: "desktopcomputer", title: "Wine", desc: "Runs Windows applications on iOS")
            infoRow(icon: "paintbrush", title: "MoltenVK", desc: "Translates Vulkan API to Apple Metal")
            infoRow(icon: "gamecontroller", title: "DXVK", desc: "Translates DirectX 11 to Vulkan")
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

            let box64Path = docs.appendingPathComponent("Box64/box64").path
            box64Status = fm.fileExists(atPath: box64Path) ? .ok : .missing

            let winePath = docs.appendingPathComponent("Wine/wine64").path
            wineStatus = fm.fileExists(atPath: winePath) ? .ok : .missing

            metalStatus = MTLCreateSystemDefaultDevice() != nil ? .ok : .missing

            jitStatusCheck = jitManager.isJITEnabled ? .ok : .missing
        }
    }

    private func openFilesApp() {
        let url = URL(fileURLWithPath: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].path)
        UIApplication.shared.open(url)
    }
}

struct SetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepCard(num: 1, title: "Download Binaries", body: """
                    You need pre-compiled binaries for iOS:
                    - box64 (ARM64 iOS binary)
                    - wine64 (ARM64 iOS binary)
                    - rootfs.tar.zst (Wine root filesystem)
                    
                    These can be compiled from source using the build scripts in Scripts/ folder.
                    """)

                stepCard(num: 2, title: "Transfer via iTunes/Finder", body: """
                    1. Connect your iPhone to your Mac/PC
                    2. Open Finder (macOS) or iTunes (Windows)
                    3. Select your iPhone → File Sharing → GameHub
                    4. Drag and drop: box64, wine64, rootfs.tar.zst
                    """)

                stepCard(num: 3, title: "Transfer via Files App", body: """
                    1. Copy binaries to iCloud Drive or Google Drive
                    2. Open Files app on iPhone
                    3. Navigate to GameHub folder
                    4. Copy the binaries into the Box64/ and Wine/ folders
                    """)

                stepCard(num: 4, title: "Transfer via WebDAV", body: """
                    1. In GameHub, go to Import → WebDAV
                    2. Start the WebDAV server
                    3. On your computer, open a WebDAV client
                    4. Connect to the shown IP address
                    5. Upload the binaries
                    """)

                stepCard(num: 5, title: "Enable JIT", body: """
                    For best performance, enable JIT:
                    1. Install StikDebug from the App Store
                    2. Open StikDebug → Enable JIT for GameHub
                    3. Return to GameHub
                    """)

                stepCard(num: 6, title: "Add Games", body: """
                    1. Import .exe game files into GameHub
                    2. Create a Container for each game
                    3. Tap Play to launch!
                    """)

                VStack(alignment: .leading, spacing: 8) {
                    Text("File Locations")
                        .font(.headline)

                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

                    fileLoc("Box64 binary", path: docs.appendingPathComponent("Box64/box64").path)
                    fileLoc("Wine binary", path: docs.appendingPathComponent("Wine/wine64").path)
                    fileLoc("Root filesystem", path: docs.appendingPathComponent("Wine/rootfs.tar.zst").path)
                    fileLoc("Games folder", path: docs.appendingPathComponent("Containers").path)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Setup Guide")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func stepCard(num: Int, title: String, body: String) -> some View {
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

    private func fileLoc(_ name: String, path: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(name).font(.caption).fontWeight(.medium)
            Text(path).font(.caption2).foregroundColor(.secondary).textSelection(.enabled)
        }
    }
}
