import SwiftUI

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."

    private static let logFile: URL? = {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("setup_memory.log")
    }()

    private static func memMB() -> UInt64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let r = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return r == KERN_SUCCESS ? UInt64(info.resident_size) / (1024 * 1024) : 0
    }

    private static func logMem(_ stage: String) {
        let mb = memMB()
        let line = "[MEM] \(stage): \(mb)MB\n"
        guard let url = logFile else { return }
        if let fh = FileHandle(forWritingAtPath: url.path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8) ?? Data())
            fh.closeFile()
        } else {
            try? line.data(using: .utf8)?.write(to: url)
        }
    }

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
                startMemoryPressureMonitor()
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
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                DispatchQueue.main.async { self.isLoading = false }
                return
            }

            Self.logMem("start")
            self.updateProgress("Creating directories...")
            let dirs = ["Box64", "Containers", "Graphics"]
            for dir in dirs {
                try? fm.createDirectory(at: docs.appendingPathComponent(dir), withIntermediateDirectories: true)
            }
            Self.logMem("dirs created")

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
            Self.logMem("extraction done")

            autoreleasepool {
                self.updateProgress("Initializing Box64...")
                Self.logMem("before Box64 init")
                Box64Bridge.shared.initialize()
                Self.logMem("after Box64 init")
            }

            autoreleasepool {
                self.updateProgress("Initializing Wine...")
                Self.logMem("before Wine init")
                WineBridge.shared.initialize()
                Self.logMem("after Wine init")
            }

            autoreleasepool {
                self.updateProgress("Setting up prefix...")
                Self.logMem("before prefix init")
                WinePrefixManager.shared.initializePrefix()
                Self.logMem("after prefix init")
            }

            autoreleasepool {
                self.updateProgress("Applying settings...")
                Self.logMem("before applySettings")
                settingsManager.applySettings()
                Self.logMem("after applySettings - DONE")
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

    private func startMemoryPressureMonitor() {
        let source = DispatchSource.makeMemoryPressureSource(
            eventMask: [.warning, .critical],
            queue: .global(qos: .utility)
        )
        source.setEventHandler {
            let mb = Self.memMB()
            Self.logMem("MEMORY_PRESSURE mem=\(mb)MB")
            if mb > 1400 {
                Self.logMem("CRITICAL: exceeding 1400MB, clearing caches")
                URLCache.shared.removeAllCachedResponses()
                NotificationCenter.default.post(name: .init("MemoryPressureCritical"), object: nil)
            }
        }
        source.resume()
    }
}
