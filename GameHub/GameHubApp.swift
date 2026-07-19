import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."

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

            Text("MN emulator")
                .font(.largeTitle).bold()

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline).foregroundColor(.secondary)

            Text("Created by @R_MOX")
                .font(.caption).foregroundColor(.secondary)

            if let error = setupError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
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
                }
            }
        }
        .padding()
    }

    private func performSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            self.updateProgress("Creating directories...")
            let dirs = ["Box64", "Containers", "Graphics"]
            for dir in dirs {
                try? fm.createDirectory(at: docs.appendingPathComponent(dir), withIntermediateDirectories: true)
            }

            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

            if !box64Exists || !wineExists {
                self.updateProgress("Extracting bundled binaries...")
                do {
                    try autoreleasepool {
                        try Box64Bridge.shared.setupAllBundledBinaries { detail in
                            self.updateProgress(detail)
                        }
                    }
                } catch {
                    print("[MNEmulator] Extraction error: \(error)")
                    DispatchQueue.main.async {
                        self.setupError = "Extraction error: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                    return
                }
            }

            autoreleasepool {
                self.updateProgress("Initializing Box64...")
                Box64Bridge.log("performSetup: before Box64 init")
                Box64Bridge.shared.initialize()
                Box64Bridge.log("performSetup: after Box64 init, isInitialized=\(Box64Bridge.shared.isSetupComplete)")
            }

            autoreleasepool {
                self.updateProgress("Initializing Wine...")
                Box64Bridge.log("performSetup: before Wine init")
                WineBridge.shared.initialize()
                Box64Bridge.log("performSetup: after Wine init")
            }

            autoreleasepool {
                self.updateProgress("Setting up prefix...")
                Box64Bridge.log("performSetup: before prefix init")
                WinePrefixManager.shared.initializePrefix()
                Box64Bridge.log("performSetup: after prefix init")
            }

            autoreleasepool {
                self.updateProgress("Applying settings...")
                Box64Bridge.log("performSetup: before applySettings")
                settingsManager.applySettings()
                Box64Bridge.log("performSetup: after applySettings - DONE")
            }

            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.3)) {
                    self.isLoading = false
                }
            }
        }
    }

    private func updateProgress(_ text: String) {
        DispatchQueue.main.async {
            self.setupProgress = text
        }
    }
}
