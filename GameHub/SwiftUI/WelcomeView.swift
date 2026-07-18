import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @State private var box64Found = false
    @State private var wineFound = false
    @State private var metalAvailable = false

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    headerSection
                    statusSection
                    setupSection
                    howItWorksSection
                }
                .padding()
            }
            .navigationTitle("GameHub")
            .onAppear { checkStatus() }
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
        }
        .padding(.top, 10)
    }

    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("System Status")
                .font(.headline)

            statusRow(icon: "cpu", name: "Box64", ok: box64Found, detail: "x86_64 → ARM64 translator")
            statusRow(icon: "desktopcomputer", name: "Wine", ok: wineFound, detail: "Windows API layer")
            statusRow(icon: "paintbrush", name: "Metal", ok: metalAvailable, detail: "GPU graphics")
            statusRow(icon: "bolt.fill", name: "JIT", ok: jitManager.isJITEnabled, detail: "Performance mode")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func statusRow(icon: String, name: String, ok: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(ok ? .green : .red)
                .frame(width: 24)
            VStack(alignment: .leading) {
                Text(name).font(.subheadline).fontWeight(.medium)
                Text(detail).font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
        }
    }

    private var setupSection: some View {
        VStack(spacing: 12) {
            if box64Found && wineFound {
                NavigationLink(destination: GameLibraryView()
                    .environmentObject(containerManager)
                    .environmentObject(jitManager)) {
                    Label("Start Playing", systemImage: "gamecontroller.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
                .onTapGesture {
                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                }
            } else {
                NavigationLink(destination: SetupGuideView()) {
                    Label("Setup Guide", systemImage: "book.fill")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }

                Button(action: openInFilesApp) {
                    Label("Import Binaries via Files App", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.orange)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
    }

    private var howItWorksSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How it works")
                .font(.headline)

            infoRow(icon: "cpu", title: "Box64", desc: "Translates x86_64 Linux binaries to ARM64")
            infoRow(icon: "desktopcomputer", title: "Wine", desc: "Runs Windows applications on iOS")
            infoRow(icon: "paintbrush", title: "MoltenVK", desc: "Vulkan API → Apple Metal")
            infoRow(icon: "gamecontroller", title: "DXVK", desc: "DirectX 11 → Vulkan")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func infoRow(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(.blue).frame(width: 24)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).fontWeight(.medium)
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
    }

    private func checkStatus() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]

        box64Found = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        wineFound = fm.fileExists(atPath: docs.appendingPathComponent("Wine/wine64").path)
        metalAvailable = MTLCreateSystemDefaultDevice() != nil
    }

    private func openInFilesApp() {
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        UIApplication.shared.open(url)
    }
}

struct SetupGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                stepCard(num: 1, title: "Download Binaries", body: """
                    You need pre-compiled binaries for iOS:
                    - box64 (ARM64 Mach-O binary)
                    - wine64 (ARM64 Mach-O binary)
                    - rootfs.tar.zst (Wine root filesystem)
                    """)

                stepCard(num: 2, title: "Transfer via iTunes/Finder", body: """
                    1. Connect iPhone to Mac/PC
                    2. Open Finder (macOS) or iTunes (Windows)
                    3. Select iPhone → File Sharing → GameHub
                    4. Drag: box64, wine64, rootfs.tar.zst
                    """)

                stepCard(num: 3, title: "Transfer via Files App", body: """
                    1. Copy binaries to iCloud Drive
                    2. Open Files app on iPhone
                    3. Navigate to GameHub folder
                    4. Move to Box64/ and Wine/ folders
                    """)

                stepCard(num: 4, title: "Transfer via WebDAV", body: """
                    Use any WebDAV client (Cyberduck, WinSCP)
                    Connect to your iPhone's IP address
                    Upload to GameHub's Documents folder
                    """)

                stepCard(num: 5, title: "Enable JIT", body: """
                    1. Install StikDebug from App Store
                    2. Open StikDebug → Enable JIT for GameHub
                    3. Return to GameHub
                    """)

                stepCard(num: 6, title: "Add Games", body: """
                    1. Import .exe game files
                    2. Create a Container for each game
                    3. Tap Play!
                    """)

                VStack(alignment: .leading, spacing: 8) {
                    Text("File Locations")
                        .font(.headline)

                    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

                    fileLoc("Box64", path: docs.appendingPathComponent("Box64/box64").path)
                    fileLoc("Wine", path: docs.appendingPathComponent("Wine/wine64").path)
                    fileLoc("Root FS", path: docs.appendingPathComponent("Wine/rootfs.tar.zst").path)
                    fileLoc("Games", path: docs.appendingPathComponent("Containers").path)
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
