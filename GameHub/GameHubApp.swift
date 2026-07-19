import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."
    @State private var setupLog: [String] = []
    @State private var currentStep = 0

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
        VStack(spacing: 16) {
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
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(setupProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(setupLog.enumerated()), id: \.offset) { idx, line in
                                    Text(line)
                                        .font(.system(.caption2, design: .monospaced))
                                        .foregroundColor(.green)
                                        .id(idx)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                        }
                        .frame(maxHeight: 120)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                        .onChange(of: setupLog.count) { _ in
                            withAnimation { proxy.scrollTo(setupLog.count - 1, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func logStep(_ n: Int, _ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let line = "[\(ts)] STEP \(n): \(text)"
        NSLog("%@", line)
        DispatchQueue.main.async {
            self.setupLog.append(line)
            if self.setupLog.count > 100 {
                self.setupLog.removeFirst(50)
            }
            self.currentStep = n
            self.setupProgress = text
        }
    }

    private func performSetup() {
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            logStep(1, "Checking existing files...")
            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)
            logStep(1, "Box64 exists: \(box64Exists), Wine exists: \(wineExists)")

            if !box64Exists || !wineExists {
                var stepCounter = 2
                do {
                    try Box64Bridge.shared.setupAllBundledBinaries { detail in
                        stepCounter += 1
                        self.logStep(stepCounter, detail)
                    }
                } catch {
                    logStep(-1, "EXTRACTION FAILED: \(error)")
                    DispatchQueue.main.async {
                        self.setupError = "Extraction error: \(error.localizedDescription)"
                        self.isLoading = false
                    }
                    return
                }
            }

            logStep(20, "Initializing Box64...")
            Box64Bridge.shared.initialize()
            logStep(20, "Box64 init complete")

            logStep(21, "Initializing Wine...")
            WineBridge.shared.initialize()
            logStep(21, "Wine init complete")

            logStep(22, "Setting up prefix...")
            WinePrefixManager.shared.initializePrefix()
            logStep(22, "Prefix init complete")

            logStep(23, "Applying settings...")
            settingsManager.applySettings()
            logStep(23, "ALL DONE!")

            DispatchQueue.main.async {
                withAnimation(.easeIn(duration: 0.3)) {
                    self.isLoading = false
                }
            }
        }
    }
}
