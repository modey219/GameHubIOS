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

@main
struct GameHubApp: App {
    init() { setupCrashHandler() }
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    @State private var isLoading = true
    @State private var setupError: String?
    @State private var setupProgress = "Initializing..."
    @State private var setupLog: [String] = []
    @State private var currentStep = 0
    @State private var cDiagLog: String = ""
    @State private var showShareSheet = false
    @State private var shareText: String = ""

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
                UserDefaults.standard.set(false, forKey: "_crash_sentinel")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    performSetup()
                }
            }
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [shareText])
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
                    Text(verbatim: error)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    if !cDiagLog.isEmpty {
                        ScrollView {
                            Text(verbatim: cDiagLog)
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
                    Text(verbatim: setupProgress)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(setupLog.enumerated()), id: \.offset) { idx, line in
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
                        .onChange(of: setupLog.count) { _ in
                            if setupLog.count > 0 {
                                withAnimation { proxy.scrollTo(setupLog.count - 1, anchor: .bottom) }
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }

    private func logStep(_ n: Int, _ text: String) {
        let ts = ISO8601DateFormatter().string(from: Date()) ?? "unknown"
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

    private func readCdiagLog() {
        guard let p = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return }
        let cdiagPath = p + "/c_diag.log"
        let diagPath = p + "/diag.log"
        let cdiag = (try? String(contentsOfFile: cdiagPath, encoding: .utf8)) ?? ""
        let diag = (try? String(contentsOfFile: diagPath, encoding: .utf8)) ?? ""
        var combined = ""
        if !cdiag.isEmpty { combined += "=== c_diag.log ===\n\(cdiag)\n" }
        if !diag.isEmpty { combined += "=== diag.log ===\n\(diag)\n" }
        cDiagLog = combined.isEmpty ? "(no log files found)" : combined
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
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                DispatchQueue.main.async {
                    withAnimation(.easeIn(duration: 0.3)) {
                        self.isLoading = false
                    }
                }
            }

            let fm = FileManager.default
            guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
                writeDiag("FAIL: no docs dir")
                UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                return
            }

            let alreadyLaunched = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
            let box64Exists = fm.fileExists(atPath: docs.appendingPathComponent("Box64/box64").path)
            let wineExists = fm.fileExists(atPath: docs.appendingPathComponent("Wine/bin/wine64").path)

            if alreadyLaunched && box64Exists && wineExists {
                writeDiag("step=skip_init_already_launched")
                logStep(1, "Quick launch (already initialized)...")
                return
            }

            writeDiag("step=clean")
            logStep(1, "Cleaning stale 0-byte files...")
            for stalePath in ["Box64/box64", "Wine/bin/wine64", "Wine/bin/wine", "Wine/bin/wineserver", "Wine/bin/wineboot"] {
                let fullPath = docs.appendingPathComponent(stalePath).path
                if fm.fileExists(atPath: fullPath),
                   let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let size = attrs[.size] as? NSNumber,
                   size.intValue == 0 {
                    try? fm.removeItem(atPath: fullPath)
                    logStep(1, "Removed stale 0-byte file: \(stalePath)")
                }
            }

            writeDiag("step=check")
            logStep(1, "Checking existing files...")
            logStep(1, "Box64 exists: \(box64Exists), Wine exists: \(wineExists)")

            if !box64Exists || !wineExists {
                writeDiag("step=extract")
                var stepCounter = 2
                do {
                    try Box64Bridge.shared.setupAllBundledBinaries { detail in
                        stepCounter += 1
                        self.logStep(stepCounter, detail)
                    }
                } catch {
                    writeDiag("extraction_failed=\(error)")
                    logStep(-1, "EXTRACTION FAILED: \(error)")
                    UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
                    DispatchQueue.main.async {
                        self.setupError = "Extraction error: \(error.localizedDescription)"
                        self.readCdiagLog()
                    }
                    return
                }
            }

            writeDiag("step=wine_init")
            logStep(5, "Initializing Wine...")
            do { WineBridge.shared.initialize() }
            writeDiag("step=wine_init_done")
            logStep(5, "Wine init complete")

            writeDiag("step=prefix")
            logStep(6, "Setting up prefix...")
            do { WinePrefixManager.shared.initializePrefix() }
            writeDiag("step=prefix_done")
            logStep(6, "Prefix init complete")

            writeDiag("step=box64_deferred")
            logStep(7, "Box64 will init on first game launch")

            writeDiag("step=settings")
            logStep(8, "ALL DONE!")

            writeDiag("step=all_done")
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
