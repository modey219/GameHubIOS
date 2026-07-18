import SwiftUI

struct DebugView: View {
    @State private var logs: [String] = []
    @State private var box64TestResult = "Not tested"
    @State private var wineTestResult = "Not tested"
    @State private var binariesInfo = "Checking..."
    @State private var isRunning = false

    var body: some View {
        NavigationView {
            List {
                Section("Binary Status") {
                    Text(binariesInfo)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Button("Check Binaries") {
                        checkBinaries()
                    }
                }

                Section("Tests") {
                    HStack {
                        Text("Box64")
                        Spacer()
                        Text(box64TestResult)
                            .foregroundColor(box64TestResult.contains("OK") ? .green : .red)
                    }
                    HStack {
                        Text("Wine")
                        Spacer()
                        Text(wineTestResult)
                            .foregroundColor(wineTestResult.contains("OK") ? .green : .red)
                    }
                    Button("Run Tests") {
                        runTests()
                    }
                    .disabled(isRunning)
                }

                Section("Console Log") {
                    if logs.isEmpty {
                        Text("No logs yet")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(logs.reversed(), id: \.self) { log in
                            Text(log)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    Button("Clear Logs") { logs.removeAll() }
                }
            }
            .navigationTitle("Diagnostics")
        }
        .onAppear { checkBinaries() }
    }

    private func log(_ msg: String) {
        let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append("[\(ts)] \(msg)")
    }

    private func checkBinaries() {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return }

        var info: [String] = []

        let box64Path = docs.appendingPathComponent("Box64/box64").path
        let box64Exists = fm.fileExists(atPath: box64Path)
        info.append("Box64: \(box64Exists ? "YES" : "NO")")
        if box64Exists {
            if let attrs = try? fm.attributesOfItem(atPath: box64Path),
               let size = attrs[.size] as? Int {
                info.append("  Size: \(size / 1024)KB")
            }
        }

        let wine64Path = docs.appendingPathComponent("Wine/bin/wine64").path
        let wine64Exists = fm.fileExists(atPath: wine64Path)
        info.append("Wine64: \(wine64Exists ? "YES" : "NO")")

        let mvkPath = docs.appendingPathComponent("Graphics/MoltenVK")
        let mvkExists = fm.fileExists(atPath: mvkPath.path)
        info.append("MoltenVK: \(mvkExists ? "YES" : "NO")")

        let dxvkPath = docs.appendingPathComponent("Graphics/DXVK")
        let dxvkExists = fm.fileExists(atPath: dxvkPath.path)
        info.append("DXVK: \(dxvkExists ? "YES" : "NO")")

        binariesInfo = info.joined(separator: "\n")
        log("Binary check complete")
    }

    private func runTests() {
        isRunning = true
        box64TestResult = "Testing..."
        wineTestResult = "Testing..."
        log("Starting tests...")

        DispatchQueue.global(qos: .userInitiated).async {
            let box64Result = testBox64()
            DispatchQueue.main.async {
                box64TestResult = box64Result
                log("Box64 test: \(box64Result)")
            }

            let wineResult = testWine()
            DispatchQueue.main.async {
                wineTestResult = wineResult
                log("Wine test: \(wineResult)")
                isRunning = false
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
            return "FAIL: Not found"
        }

        // Try to run box64 --version
        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64Path)
        process.arguments = ["--version"]

        let pipe = iOSPipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe?.readHandle.readDataToEndOfFile() ?? Data()
            let output = String(data: data, encoding: .utf8) ?? "no output"
            if process.terminationStatus == 0 {
                return "OK: \(output.prefix(80))"
            } else {
                return "EXIT \(process.terminationStatus): \(output.prefix(80))"
            }
        } catch {
            return "FAIL: \(error.localizedDescription.prefix(80))"
        }
    }

    private func testWine() -> String {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return "FAIL: No docs dir"
        }
        let wine64Path = docs.appendingPathComponent("Wine/bin/wine64").path

        guard fm.fileExists(atPath: wine64Path) else {
            return "FAIL: Not found"
        }

        // Check if it's actually executable
        let attrs = try? fm.attributesOfItem(atPath: wine64Path)
        if let perm = attrs?[.posixPermissions] as? Int {
            if perm & 0o111 == 0 {
                return "FAIL: Not executable (mode \(String(perm, radix: 8)))"
            }
        }

        // Wine is x86_64 Linux - can't run natively, only via box64
        return "OK: Present (needs box64 to run)"
    }
}
