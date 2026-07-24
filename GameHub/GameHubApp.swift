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

class SetupState: ObservableObject {
    @Published var isLoading = true
    @Published var setupError: String?
    @Published var setupProgress = "Initializing..."
    @Published var setupLog: [String] = []
    @Published var currentStep = 0
    @Published var cDiagLog: String = ""

    func logStep(_ n: Int, _ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date()) ?? "unknown"
        let line = "[\(ts)] STEP \(n): \(text)"
        NSLog("%@", line)
        Task { @MainActor in
            self.setupLog.append(line)
            if self.setupLog.count > 100 { self.setupLog.removeFirst(50) }
            self.currentStep = n
            self.setupProgress = text
        }
    }

    func finishLoading() {
        NSLog("[MNEmulator] finishLoading() called — about to dispatch to main")
        Task { @MainActor in
            NSLog("[MNEmulator] finishLoading() executing on main thread — isLoading was \(self.isLoading)")
            self.objectWillChange.send()
            self.isLoading = false
            NSLog("[MNEmulator] finishLoading() done — isLoading is now \(self.isLoading)")
        }
    }

    func showError(_ msg: String) {
        Task { @MainActor in
            self.setupError = msg
        }
    }

    func readCdiagLog() {
        guard let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return }
        let cdiagPath = p + "/c_diag.log"
        let diagPath = p + "/diag.log"
        let cdiag = (try? String(contentsOfFile: cdiagPath, encoding: .utf8)) ?? ""
        let diag = (try? String(contentsOfFile: diagPath, encoding: .utf8)) ?? ""
        var combined = ""
        if !cdiag.isEmpty { combined += "=== c_diag.log ===\n\(cdiag)\n" }
        if !diag.isEmpty { combined += "=== diag.log ===\n\(diag)\n" }
        let result = combined.isEmpty ? "(no log files found)" : combined
        Task { @MainActor in
            self.cDiagLog = result
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
    @StateObject private var setupState = SetupState()
    @State private var showShareSheet = false
    @State private var shareText: String = ""
    @State private var safetyTimerFired = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if setupState.isLoading {
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
            UserDefaults.standard.set(false, forKey: "_crash_sentinel")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                performSetup()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 60) {
                if self.setupState.isLoading && !self.safetyTimerFired {
                    self.safetyTimerFired = true
                    NSLog("[MNEmulator] SAFETY TIMER fired — forcing splash dismiss after 60s")
                    self.setupState.finishLoading()
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
                .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))

            Text("MN emulator")
                .font(.largeTitle).bold()

            Text("PC Game Emulator for iPhone & iPad")
                .font(.subheadline).foregroundColor(.secondary)

            Text("Created by @R_MOX")
                .font(.caption).foregroundColor(.secondary)

            if let error = setupState.setupError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.title2)
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if !setupState.cDiagLog.isEmpty {
                        ScrollView {
                            Text(verbatim: setupState.cDiagLog)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(maxHeight: 200)
                        .background(Color.black.opacity(0.8))
                        .cornerRadius(8)
                        .padding(.horizontal, 24)
                    }
                    HStack(spacing: 16) {
                        Button("Continue Anyway") {
                            setupState.finishLoading()
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
                    Text(verbatim: setupState.setupProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(setupState.setupLog.enumerated()), id: \.offset) { idx, line in
                                    Text(verbatim: line)
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
                        .onChange(of: setupState.setupLog.count) { _ in
                            if setupState.setupLog.count > 0 {
                                withAnimation { proxy.scrollTo(setupState.setupLog.count - 1, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
        }
        .padding()
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

    private func performSetup() {
        let state = self.setupState
        DispatchQueue.global(qos: .userInitiated).async {
            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                writeDiag("FAIL: no docs dir")
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                state.finishLoading()
                return
            }

            let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

            if alreadyLaunched && box64Exists && wineExists {
                writeDiag("step=skip_init_already_launched")
                state.logStep(1, "Quick launch (already initialized)...")
                state.finishLoading()
                return
            }

            writeDiag("step=clean")
            state.logStep(1, "Cleaning stale 0-byte files...")
            for stalePath in ["Box64/box64", "Wine/bin/wine64", "Wine/bin/wine", "Wine/bin/wineserver", "Wine/bin/wineboot"] {
                let fullPath = docs.appendingPathComponent(stalePath).path
                if fm.fileExists(atPath: fullPath),
                   let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? NSNumber,
                   size.intValue == 0 {
                    try? fm.removeItem(atPath: fullPath)
                    state.logStep(1, "Removed stale 0-byte file: \(stalePath)")
                }
            }

            writeDiag("step=check")
            state.logStep(1, "Checking existing files...")
            state.logStep(1, "Box64 exists: \(box64Exists), Wine exists: \(wineExists)")

            if !box64Exists || !wineExists {
                writeDiag("step=extract")
                var stepCounter = 2
                do {
                    try Box64Bridge.shared.setupAllBundledBinaries { detail in
                        stepCounter += 1
                        state.logStep(stepCounter, detail)
                    }
                } catch {
                    writeDiag("extraction_failed=\(error)")
                    state.logStep(-1, "EXTRACTION FAILED: \(error)")
                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                    state.showError("Extraction error: \(error.localizedDescription)")
                    state.readCdiagLog()
                    return
                }
            }

            writeDiag("step=wine_init")
            state.logStep(5, "Initializing Wine...")
            do { WineBridge.shared.initialize() }
            writeDiag("step=wine_init_done")
            state.logStep(5, "Wine init complete")

            writeDiag("step=prefix")
            state.logStep(6, "Setting up prefix...")
            do { WinePrefixManager.shared.initializePrefix() }
            writeDiag("step=prefix_done")
            state.logStep(6, "Prefix init complete")

            writeDiag("step=box64_deferred")
            state.logStep(7, "Box64 will init on first game launch")

            writeDiag("step=settings")
            state.logStep(8, "ALL DONE!")

            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            writeDiag("step=all_done")
            state.finishLoading()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
