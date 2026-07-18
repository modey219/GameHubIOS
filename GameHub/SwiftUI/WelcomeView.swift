import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var step = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    header
                    if step == 0 { welcomeStep }
                    else if step == 1 { setupStep }
                    else { readyStep }
                }
                .padding(24)
            }
            .background(Color(.systemBackground))
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Text("GameHub")
                .font(.largeTitle).bold()
            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline).foregroundColor(.secondary)
        }
        .padding(.top, 20)
    }

    private var welcomeStep: some View {
        VStack(spacing: 20) {
            featureCard(icon: "cpu", title: "Box64", desc: "x86_64 to ARM64 translation layer")
            featureCard(icon: "desktopcomputer", title: "Wine 9.0", desc: "Windows API implementation for iOS")
            featureCard(icon: "paintbrush", title: "MoltenVK + DXVK", desc: "Vulkan/DirectX to Metal translation")
            featureCard(icon: "gamecontroller", title: "Virtual Gamepad", desc: "On-screen controls with physical controller support")

            Button(action: { withAnimation { step = 1 } }) {
                Text("Get Started")
                    .fontWeight(.bold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }

    private var setupStep: some View {
        VStack(spacing: 16) {
            Text("Transfer Binaries")
                .font(.title3).bold()

            setupMethod(icon: "desktopcomputer", title: "Via Computer", desc: "Connect iPhone → Open Finder/iTunes → File Sharing → GameHub → Copy files")

            setupMethod(icon: "folder", title: "Via Files App", desc: "Copy to iCloud Drive → Open Files app → Move to GameHub folder")

            setupMethod(icon: "wifi", title: "Via Network", desc: "Use WebDAV client (Cyberduck) → Connect to iPhone IP → Upload files")

            VStack(alignment: .leading, spacing: 8) {
                Text("Required Files:").font(.headline)
                fileRow("box64", "Box64/")
                fileRow("wine64", "Wine/")
                fileRow("wineserver", "Wine/")
                fileRow("rootfs.tar.zst", "Wine/")
                fileRow("MoltenVK dylib", "Graphics/MoltenVK/")
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)

            HStack(spacing: 12) {
                Button(action: { step = 0 }) {
                    Text("Back").frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray5)).cornerRadius(12)
                }
                Button(action: { withAnimation { step = 2 } }) {
                    Text("Continue").fontWeight(.bold).frame(maxWidth: .infinity).padding()
                        .background(Color.blue).foregroundColor(.white).cornerRadius(12)
                }
            }
        }
    }

    private var readyStep: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundColor(.green)

            Text("You're All Set!")
                .font(.title2).bold()

            let fm = FileManager.default
            let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            let box64 = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wine = fm.fileExists(atPath: docs.appendingPathComponent("Wine/wine64").path)

            if box64 && wine {
                statusBadge("Box64", ok: true)
                statusBadge("Wine", ok: true)
            } else {
                if !box64 { statusBadge("Box64 - not found", ok: false) }
                if !wine { statusBadge("Wine - not found", ok: false) }
                Text("You can still explore the app. Binaries can be added later via Files app.")
                    .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
            }

            Button(action: onComplete) {
                Text("Start Using GameHub")
                    .fontWeight(.bold).frame(maxWidth: .infinity).padding()
                    .background(Color.green).foregroundColor(.white).cornerRadius(12)
            }
        }
    }

    private func featureCard(icon: String, title: String, desc: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title2).foregroundColor(.blue).frame(width: 36)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).bold()
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func setupMethod(icon: String, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).foregroundColor(.blue).frame(width: 24)
            VStack(alignment: .leading) {
                Text(title).font(.subheadline).bold()
                Text(desc).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(10)
    }

    private func fileRow(_ name: String, _ dest: String) -> some View {
        HStack {
            Image(systemName: "doc").foregroundColor(.blue)
            Text(name).font(.caption).bold()
            Spacer()
            Text("→ \(dest)").font(.caption2).foregroundColor(.secondary)
        }
    }

    private func statusBadge(_ text: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
            Text(text).font(.subheadline)
        }
    }
}
