import Foundation
import Combine

class SetupManager: ObservableObject {
    @Published var isSetupComplete = false
    @Published var setupMessage = "Preparing..."
    @Published var setupProgress: Double = 0

    private let box64Bridge = Box64Bridge.shared

    func performSetup() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            Self.writeDiag("bg_setup_start")

            DispatchQueue.main.async { self.setupMessage = "Extracting Box64..." }

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
                Self.writeDiag("bg_setup_extract_error: \(error.localizedDescription)")
                NSLog("[MNEmulator] extraction failed: %@", error.localizedDescription)
            }

            DispatchQueue.main.async {
                self.setupMessage = "Initializing Wine..."
                self.setupProgress = 0.6
            }

            Self.writeDiag("bg_wine_init")
            WineBridge.shared.initialize()
            Self.writeDiag("bg_prefix_init")
            WinePrefixManager.shared.initializePrefix()

            DispatchQueue.main.async {
                self.setupProgress = 1.0
                self.setupMessage = "Ready"
                self.isSetupComplete = true
                Self.writeDiag("bg_setup_done")
                NSLog("[MNEmulator] SetupManager: setup complete")
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
