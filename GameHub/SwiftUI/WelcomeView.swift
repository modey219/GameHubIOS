import SwiftUI

struct WelcomeView: View {
    let onComplete: () -> Void
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var step = 0
    @State private var isExtracting = false
    @State private var extractionStatus = ""
    @State private var extractionError: String?

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
            featureCard(icon: "desktopcomputer", title: "Wine 9.21", desc: "Windows API implementation for iOS")
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
            Text("Setup")
                .font(.title3).bold()

            if isExtracting {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(extractionStatus)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let error = extractionError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Box64 x86_64 translator")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Wine 9.21 Windows API")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("MoltenVK Vulkan → Metal")
                    }
                    HStack(spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("DXVK DirectX 11 → Vulkan")
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)

                Text("All components are bundled in the app. Tap below to extract and prepare them.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 12) {
                Button(action: { step = 0 }) {
                    Text("Back").frame(maxWidth: .infinity).padding()
                        .background(Color(.systemGray5)).cornerRadius(12)
                }
                Button(action: {
                    isExtracting = true
                    extractionStatus = "Extracting binaries..."
                    DispatchQueue.global(qos: .userInitiated).async {
                        do {
                            try Box64Bridge.shared.setupAllBundledBinaries { detail in
                                DispatchQueue.main.async {
                                    self.extractionStatus = detail
                                }
                            }
                            DispatchQueue.main.async {
                                isExtracting = false
                                withAnimation { step = 2 }
                            }
                        } catch {
                            DispatchQueue.main.async {
                                isExtracting = false
                                extractionError = error.localizedDescription
                            }
                        }
                    }
                }) {
                    Text(isExtracting ? "Extracting..." : "Extract & Continue")
                        .fontWeight(.bold).frame(maxWidth: .infinity).padding()
                        .background(isExtracting ? Color.gray : Color.blue)
                        .foregroundColor(.white).cornerRadius(12)
                }
                .disabled(isExtracting)
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

            VStack(spacing: 8) {
                statusBadge("Box64", ok: true)
                statusBadge("Wine", ok: true)
                statusBadge("MoltenVK", ok: true)
                statusBadge("DXVK", ok: true)
            }

            Text("All components are ready. Add games via the Games tab, then launch and play!")
                .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)

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

    private func statusBadge(_ text: String, ok: Bool) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(ok ? .green : .red)
            Text(text).font(.subheadline)
        }
    }
}
