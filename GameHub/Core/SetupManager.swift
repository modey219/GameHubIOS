import Foundation
import Combine

class SetupManager: ObservableObject {
    @Published var isSetupComplete = false
    @Published var setupMessage = ""
    @Published var setupProgress: Double = 0

    private let box64Bridge = Box64Bridge.shared

    var isExtractionDone: Bool {
        let fm = FileManager.default
        guard let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
        let box64 = docs.appendingPathComponent("Box64/box64").path
        let wine64 = docs.appendingPathComponent("Wine/bin/wine64").path
        return fm.fileExists(atPath: box64) && fm.fileExists(atPath: wine64)
    }

    func checkReady() {
        if isExtractionDone {
            isSetupComplete = true
        }
    }

    func ensureReady(completion: @escaping (Bool, String) -> Void) {
        if isSetupComplete {
            completion(true, "Ready")
            return
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            Self.writeDiag("ensureReady_start")

            DispatchQueue.main.async {
                self.setupMessage = "Extracting binaries..."
                self.setupProgress = 0.1
            }

            do {
                try self.box64Bridge.setupAllBundledBinaries { detail in
                    DispatchQueue.main.async {
                        self.setupMessage = detail
                        if detail.contains("done") {
                            self.setupProgress = 0.5
                        } else if detail.contains("Copying") {
                            self.setupProgress = 0.3
                        }
                    }
                }
            } catch {
                Self.writeDiag("ensureReady_extract_error: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(false, "Extraction failed: \(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.setupMessage = "Initializing Wine..."
                self.setupProgress = 0.7
            }

            Self.writeDiag("ensureReady_wine_init")
            WineBridge.shared.initialize()

            Self.writeDiag("ensureReady_prefix_init")
            WinePrefixManager.shared.initializePrefix()

            Self.writeDiag("ensureReady_done")

            DispatchQueue.main.async {
                self.setupProgress = 1.0
                self.setupMessage = "Ready"
                self.isSetupComplete = true
                completion(true, "Ready")
            }
        }
    }

    private static func writeDiag(_ s: String) {
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
}
