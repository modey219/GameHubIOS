import SwiftUI
import UIKit

struct DebugView: View {
    @EnvironmentObject var jitManager: JITManager
    @State private var logs: [String] = []
    @State private var binariesInfo = "Tap 'Check Binaries' to scan"
    @State private var box64TestResult = "Not tested"
    @State private var wineTestResult = "Not tested"
    @State private var launchTestResult = "Not tested"
    @State private var isRunning = false
    @State private var showCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    binarySection
                    testSection
                    launchTestSection
                    logSection
                }
                .padding()
            }
            .navigationTitle("Diagnostics")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button(action: loadLogFile) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.down.doc")
                                Text("Load Log")
                            }
                            .font(.caption)
                        }
                        Button(action: copyLogs) {
                            HStack(spacing: 4) {
                                Image(systemName: "doc.on.doc")
                                Text("Copy")
                            }
                            .font(.caption)
                        }
                        Button(action: { logs.removeAll() }) {
                            HStack(spacing: 4) {
                                Image(systemName: "trash")
                                Text("Clear")
                            }
                            .font(.caption)
                            .foregroundColor(.red)
                        }
                    }
                }
            }
            .overlay(alignment: .top) {
                if showCopied {
                    Text("Logs copied!")
                        .font(.caption).bold()
                        .padding(.horizontal, 16).padding(.vertical, 8)
                        .background(Color.black.opacity(0.8))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
        }
    }

    private var binarySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "list.bullet.rectangle")
                    .foregroundColor(.blue)
                Text("Binary Status").font(.headline)
                Spacer()
                Button("Check") { checkBinaries() }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            Text(binariesInfo)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var testSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "testtube.2")
                    .foregroundColor(.purple)
                Text("Binary Tests").font(.headline)
                Spacer()
                Button(action: runTests) {
                    Text(isRunning ? "Running..." : "Run Tests")
                }
                .buttonStyle(.bordered).controlSize(.small)
                .disabled(isRunning)
            }

            testRow("Box64", result: box64TestResult)
            testRow("Wine", result: wineTestResult)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var launchTestSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "play.circle")
                    .foregroundColor(.green)
                Text("Box64 Launch Test").font(.headline)
            }
            Text("Tests if box64 can actually execute on this device.")
                .font(.caption).foregroundColor(.secondary)

            Button(action: testLaunch) {
                Label("Test box64 launch", systemImage: "bolt.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(isRunning)

            if launchTestResult != "Not tested" {
                Text(launchTestResult)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(launchTestResult.contains("OK") ? .green : .red)
                    .textSelection(.enabled)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.orange)
                Text("Console Log").font(.headline)
                Spacer()
            }
            if logs.isEmpty {
                Text("No logs yet")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(logs.indices, id: \.self) { i in
                            Text(logs[i])
                                .font(.system(.caption2, design: .monospaced))
                                .textSelection(.enabled)
                                .foregroundColor(.primary)
                        }
                    }
                    .padding(8)
                }
                .frame(maxHeight: 300)
                .background(Color.black)
                .foregroundColor(.green)
                .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func testRow(_ name: String, result: String) -> some View {
        HStack {
            Text(name).font(.subheadline)
            Spacer()
            Text(result)
                .font(.caption)
                .foregroundColor(result.contains("OK") ? .green : .red)
        }
    }

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(msg)")
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
    }

    private func checkBinaries() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        var info: [String] = []

        let box64Path = docs.appendingPathComponent("Box64/box64").path
        if fm.fileExists(atPath: box64Path) {
            if let attrs = try? fm.attributesOfItem(atPath: box64Path),
               let size = attrs[.size] as? Int {
                info.append("Box64: YES (\(size / 1024)KB)")
                if let perm = attrs[.posixPermissions] as? Int {
                    info.append("  Perms: \(String(perm, radix: 8))")
                }
            } else {
                info.append("Box64: YES (size unknown)")
            }
        } else {
            info.append("Box64: NOT FOUND")
        }

        let wine64Path = docs.appendingPathComponent("Wine/bin/wine64").path
        info.append("Wine64: \(fm.fileExists(atPath: wine64Path) ? "YES" : "NOT FOUND")")

        let wineserverPath = docs.appendingPathComponent("Wine/bin/wineserver").path
        info.append("Wineserver: \(fm.fileExists(atPath: wineserverPath) ? "YES" : "NOT FOUND")")

        let mvkPath = docs.appendingPathComponent("Graphics/MoltenVK")
        info.append("MoltenVK: \(fm.fileExists(atPath: mvkPath.path) ? "YES" : "NOT FOUND")")

        let dxvkPath = docs.appendingPathComponent("Graphics/DXVK")
        info.append("DXVK: \(fm.fileExists(atPath: dxvkPath.path) ? "YES" : "NOT FOUND")")

        let containerPath = docs.appendingPathComponent("Containers")
        if let containers = try? fm.contentsOfDirectory(atPath: containerPath.path) {
            info.append("Containers: \(containers.count)")
        }

        binariesInfo = info.joined(separator: "\n")
        log("Binary check: Box64=\(fm.fileExists(atPath: box64Path)), Wine64=\(fm.fileExists(atPath: wine64Path))")
    }

    private func runTests() {
        isRunning = true
        box64TestResult = "Testing..."
        wineTestResult = "Testing..."
        log("Starting tests...")

        DispatchQueue.global(qos: .userInitiated).async {
            let box64Result = self.testBox64()
            DispatchQueue.main.async {
                self.box64TestResult = box64Result
                self.log("Box64: \(box64Result)")
            }

            let wineResult = self.testWine()
            DispatchQueue.main.async {
                self.wineTestResult = wineResult
                self.log("Wine: \(wineResult)")
                self.isRunning = false
            }
        }
    }

    private func testBox64() -> String {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "FAIL: No docs dir"
        }
        let box64Path = docs.appendingPathComponent("Box64/box64").path

        guard fm.fileExists(atPath: box64Path) else {
            return "FAIL: Binary not found"
        }

        let attrs = try? fm.attributesOfItem(atPath: box64Path)
        if let perm = attrs?[.posixPermissions] as? Int {
            if perm & 0o111 == 0 {
                try? fm.setAttributes([.posixPermissions: perm | 0o755], ofItemAtPath: box64Path)
            }
        }

        let process = NativeProcess()
        process.executableURL = URL(fileURLWithPath: box64Path)
        process.arguments = ["--version"]

        let pipe = iOSPipe()
        let errPipe = iOSPipe()
        process.standardOutput = pipe
        process.standardError = errPipe

        do {
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.1)
            }
            if process.isRunning {
                process.terminate()
                return "TIMEOUT: process did not exit within 10s"
            }
            let output = pipe?.readOutput(timeout: 2) ?? ""
            let errOutput = errPipe?.readOutput(timeout: 0.5) ?? ""
            let combined = output + (errOutput.isEmpty ? "" : "\n\(errOutput)")
            if process.terminationStatus == 0 {
                return "OK: \(combined.prefix(100))"
            } else {
                return "EXIT \(process.terminationStatus): \(combined.prefix(100))"
            }
        } catch {
            return "FAIL: \(error.localizedDescription.prefix(100))"
        }
    }

    private func testWine() -> String {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "FAIL: No docs dir"
        }
        let wine64Path = docs.appendingPathComponent("Wine/bin/wine64").path

        guard fm.fileExists(atPath: wine64Path) else {
            return "FAIL: wine64 not found"
        }

        let attrs = try? fm.attributesOfItem(atPath: wine64Path)
        if let perm = attrs?[.posixPermissions] as? Int {
            if perm & 0o111 == 0 {
                return "FAIL: Not executable (mode \(String(perm, radix: 8)))"
            }
        }

        return "OK: Present (\(Self.fileSize(wine64Path)))"
    }

    private func testLaunch() {
        isRunning = true
        launchTestResult = "Launching box64..."
        log("Testing box64 launch...")

        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            launchTestResult = "FAIL: No docs dir"
            isRunning = false
            return
        }
        let box64Path = docs.appendingPathComponent("Box64/box64").path

        guard fm.fileExists(atPath: box64Path) else {
            launchTestResult = "FAIL: box64 not found at \(box64Path)"
            isRunning = false
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let process = NativeProcess()
            process.executableURL = URL(fileURLWithPath: box64Path)
            process.arguments = ["--version"]

            let outPipe = iOSPipe()
            let errPipe = iOSPipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
                let deadline = Date().addingTimeInterval(10)
                while process.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.1)
                }
                if process.isRunning {
                    process.terminate()
                    DispatchQueue.main.async {
                        self.launchTestResult = "TIMEOUT: process did not exit within 10s"
                        self.isRunning = false
                    }
                    return
                }
                let out = outPipe?.readOutput(timeout: 3) ?? ""
                let err = errPipe?.readOutput(timeout: 1) ?? ""
                let combined = (out + (err.isEmpty ? "" : "\n\(err)")).trimmingCharacters(in: .whitespacesAndNewlines)

                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        self.launchTestResult = "OK (exit 0):\n\(combined.prefix(200))"
                        self.log("Launch test OK: \(combined.prefix(80))")
                    } else {
                        self.launchTestResult = "FAIL (exit \(process.terminationStatus)):\n\(combined.prefix(200))"
                        self.log("Launch test FAIL: \(combined.prefix(80))")
                    }
                    self.isRunning = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.launchTestResult = "FAIL: \(error.localizedDescription)"
                    self.log("Launch test error: \(error.localizedDescription)")
                    self.isRunning = false
                }
            }
        }
    }

    private func copyLogs() {
        let allLogs = logs.joined(separator: "\n")
        UIPasteboard.general.string = allLogs
        showCopied = true
        withAnimation { showCopied = false }
        log("Logs copied to clipboard")
    }

    private func loadLogFile() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let logPath = docs.appendingPathComponent("swift_box64.log").path
        guard let data = fm.contents(atPath: logPath),
              let content = String(data: data, encoding: .utf8) else {
            log("No swift_box64.log found")
            return
        }
        let lines = content.components(separatedBy: "\n").filter { !$0.isEmpty }
        logs.append(contentsOf: lines.suffix(100))
        if logs.count > 500 { logs.removeFirst(logs.count - 500) }
        log("Loaded \(min(lines.count, 100)) lines from swift_box64.log")
    }

    private static func fileSize(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64 else { return "?" }
        if size > 1024 * 1024 { return String(format: "%.1fMB", Double(size) / 1048576) }
        if size > 1024 { return "\(size / 1024)KB" }
        return "\(size)B"
    }
}
