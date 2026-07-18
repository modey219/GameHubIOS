import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."
    @State private var setupDetail = ""

    var body: some Scene {
        WindowGroup {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if isLoading {
                    splashView
                } else {
                    ContentView()
                        .environmentObject(containerManager)
                        .environmentObject(jitManager)
                        .environmentObject(settingsManager)
                        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                            jitManager.checkJITStatus()
                        }
                }
            }
            .onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    performSetup()
                }
            }
        }
    }

    private var splashView: some View {
        VStack(spacing: 20) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))

            Text("GameHub")
                .font(.largeTitle).bold()

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline).foregroundColor(.secondary)

            if let error = setupError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    Text("Setup Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)

                    Button("Continue Anyway") {
                        isLoading = false
                    }
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(12)
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(setupProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    if !setupDetail.isEmpty {
                        Text(setupDetail)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                    }
                }
            }
        }
        .padding()
    }

    private func performSetup() {
        DispatchQueue.main.async {
            self._performSetupInner()
        }
    }

    private func _performSetupInner() {
        let fm = FileManager.default

        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            isLoading = false
            return
        }

        setupProgress = "Creating directories..."
        let dirs = ["Box64", "Wine", "Wine/rootfs", "Containers", "Graphics", "Wine/input"]
        for dir in dirs {
            try? fm.createDirectory(at: docs.appendingPathComponent(dir), withIntermediateDirectories: true)
        }

        setupProgress = "Initializing graphics..."
        setupDetail = ""
        GraphicsBridge.shared.initialize()

        let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

        if !box64Exists || !wineExists {
            setupProgress = "Extracting bundled binaries..."
            do {
                try Box64Bridge.shared.setupAllBundledBinaries { detail in
                    DispatchQueue.main.async {
                        self.setupDetail = detail
                    }
                }
                setupProgress = "Binaries extracted!"
                setupDetail = ""
            } catch {
                print("[GameHub] Extraction error: \(error)")
                setupError = "Extraction error: \(error.localizedDescription)"
            }
        } else {
            setupProgress = "Using cached binaries..."
        }

        setupProgress = "Initializing Box64..."
        Box64Bridge.shared.initialize()

        setupProgress = "Initializing Wine..."
        WineBridge.shared.initialize()

        setupProgress = "Setting up prefix..."
        WinePrefixManager.shared.initializePrefix()

        setupProgress = "Applying settings..."
        settingsManager.applySettings()

        setupProgress = "Done!"
        DispatchQueue.main.async {
            withAnimation(.easeIn(duration: 0.3)) {
                self.isLoading = false
            }
        }
    }
}
