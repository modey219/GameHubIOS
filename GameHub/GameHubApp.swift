import SwiftUI
import UIKit

func setupCrashHandler() {
    NSSetUncaughtExceptionHandler { exception in
        let crash = "[Crash] ObjC exception: \(exception.name) reason=\(exception.reason ?? "nil") callStack=\(exception.callStackSymbols.joined(separator: "\n"))"
        NSLog("%@", crash)
        if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
            let log = path + "/crash.log"
            try? crash.write(toFile: log, atomically: true, encoding: .utf8)
        }
    }
    if let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
        let crashLogPath = path + "/crash.log"
        crashLogPath.withCString { install_crash_handler($0) }
        safeSetenv("CRASH_LOG_PATH", crashLogPath)
    }
}

private func writeDiag(_ s: String) {
    if let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first {
        let line = "[\(Date().timeIntervalSince1970)] \(s)\n"
        let path = p + "/diag.log"
        if let fh = FileHandle(forWritingAtPath: path) {
            fh.seekToEndOfFile()
            fh.write(line.data(using: .utf8)!)
            fh.closeFile()
        } else {
            try? line.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

@main
struct GameHubApp: App {
    init() { setupCrashHandler() }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            LaunchView(
                containerManager: containerManager,
                jitManager: jitManager,
                settingsManager: settingsManager
            )
        }
    }
}

struct LaunchView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."
    @State private var setupStep = 0
    @State private var showShareSheet = false
    @State private var shareText: String = ""
    @State private var safetyTimerFired = false

    var body: some View {
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
        .task {
            await performSetup()
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
                if isLoading {
                    NSLog("[MNEmulator] Safety timer fired — forcing dismiss of splash")
                    writeDiag("step=safety_timer_force_dismiss")
                    safetyTimerFired = true
                    isLoading = false
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            ShareSheet(activityItems: [shareText])
        }
    }

    private var splashView: some View {
        VStack(spacing: 16) {
            Image(systemName: "gamecontroller.fill")
                .font(.system(size: 64))
                .foregroundStyle(.blue)

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
                    HStack(spacing: 16) {
                        Button("Continue Anyway") {
                            isLoading = false
                        }
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        Button("Share Logs") {
                            shareLogs()
                        }
                        .padding()
                        .background(Color.gray)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(1.2)
                    Text(setupProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Text("Step \(setupStep) of 8")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
    }

    @MainActor
    private func performSetup() async {
        UserDefaults.standard.set(false, forKey: "_crash_sentinel")
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            writeDiag("FAIL: no docs dir")
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            isLoading = false
            return
        }

        let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
        let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

        if alreadyLaunched && box64Exists && wineExists {
            writeDiag("step=skip_init_already_launched")
            setupProgress = "Quick launch..."
            setupStep = 1
            isLoading = false
            return
        }

        writeDiag("step=clean")
        setupProgress = "Cleaning stale files..."
        setupStep = 1
        for stalePath in ["Box64/box64", "Wine/bin/wine64", "Wine/bin/wine", "Wine/bin/wineserver", "Wine/bin/wineboot"] {
            let fullPath = docs.appendingPathComponent(stalePath).path
            if fm.fileExists(atPath: fullPath),
               let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? NSNumber,
               size.intValue == 0 {
                try? fm.removeItem(atPath: fullPath)
            }
        }

        writeDiag("step=check")
        setupProgress = "Checking files..."
        setupStep = 1

        if !box64Exists || !wineExists {
            writeDiag("step=extract")
            setupProgress = "Extracting binaries..."
            setupStep = 2
            let extractionFailed: Bool = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do {
                        try Box64Bridge.shared.setupAllBundledBinaries { detail in
                            NSLog("[MNEmulator] extraction: %@", detail)
                        }
                        continuation.resume(returning: false)
                    } catch {
                        NSLog("[MNEmulator] extraction FAILED: %@", "\(error)")
                        writeDiag("extraction_failed=\(error)")
                        continuation.resume(returning: true)
                    }
                }
            }
            if extractionFailed {
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                setupError = "Extraction failed"
                return
            }
        }

        writeDiag("step=wine_init")
        setupProgress = "Initializing Wine..."
        setupStep = 5
        do {
            WineBridge.shared.initialize()
        } catch {
            writeDiag("wine_init_failed=\(error)")
        }
        writeDiag("step=wine_init_done")

        writeDiag("step=prefix")
        setupProgress = "Setting up prefix..."
        setupStep = 6
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                defer { continuation.resume() }
                WinePrefixManager.shared.initializePrefix()
            }
        }
        writeDiag("step=prefix_done")

        writeDiag("step=box64_deferred")
        setupProgress = "Box64 deferred..."
        setupStep = 7

        writeDiag("step=settings")
        setupProgress = "Finalizing..."
        setupStep = 8

        UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        writeDiag("step=all_done")
        setupProgress = "All done!"
        isLoading = false
    }

    private func shareLogs() {
        guard let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return }
        let diagPath = p + "/diag.log"
        let cdiagPath = p + "/c_diag.log"
        var text = "=== diag.log ===\n" + ((try? String(contentsOfFile: diagPath)) ?? "N/A") + "\n"
        text += "=== c_diag.log ===\n" + ((try? String(contentsOfFile: cdiagPath)) ?? "N/A") + "\n"
        text += "=== bridge.log ===\n" + ((try? String(contentsOfFile: p + "/bridge.log")) ?? "N/A") + "\n"
        text += "=== crash.log ===\n" + ((try? String(contentsOfFile: p + "/crash.log")) ?? "N/A") + "\n"
        UIPasteboard.general.string = text
        shareText = text
        showShareSheet = true
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
