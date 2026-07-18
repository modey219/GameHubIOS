import Foundation
import UIKit

class JITManager: ObservableObject {
    @Published var isJITEnabled = false
    @Published var jitMethod: JITMethod = .jitless
    @Published var jitStatus: JITStatus = .unknown

    enum JITMethod: String, CaseIterable {
        case stikdebug = "stikdebug"
        case jitless = "jitless"
        case sideJIT = "sidejit"

        var displayName: String {
            switch self {
            case .stikdebug: return "StikDebug (Recommended)"
            case .jitless: return "JIT-less Mode"
            case .sideJIT: return "SideJIT"
            }
        }

        var description: String {
            switch self {
            case .stikdebug: return "Enables JIT via StikDebug app."
            case .jitless: return "Run without JIT (slower)."
            case .sideJIT: return "Enable JIT via SideJIT server."
            }
        }
    }

    enum JITStatus { case unknown, enabled, disabled, enabling, unsupported }

    init() {}

    func enableJIT() {
        jitStatus = .enabling
        switch jitMethod {
        case .stikdebug: enableViaStikDebug()
        case .jitless: enableJITlessMode()
        case .sideJIT: enableViaSideJIT()
        }
    }

    private func enableViaStikDebug() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gamehub.ios"
        guard let url = URL(string: "stikdebug://enable-jit?bundle=\(bundleID)") else {
            jitStatus = .disabled; return
        }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url) { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.checkJITStatus()
                }
            }
        } else {
            jitStatus = .disabled
        }
    }

    private func enableViaSideJIT() {
        guard let url = URL(string: "sidejit://enable?pid=\(ProcessInfo.processInfo.processIdentifier)") else {
            jitStatus = .disabled; return
        }
        UIApplication.shared.open(url) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.checkJITStatus()
            }
        }
    }

    func enableJITlessMode() {
        setenv("BOX64_DYNAREC", "0", 1)
        setenv("BOX64_JITLESS", "1", 1)
        jitStatus = .enabled
        isJITEnabled = true
    }

    func checkJITStatus() {
        let dynarec = getenv("BOX64_DYNAREC")
        let enabled = dynarec != nil && String(cString: dynarec!) == "1"
        DispatchQueue.main.async {
            self.isJITEnabled = enabled
            self.jitStatus = enabled ? .enabled : .disabled
        }
    }

    func getJITInstructions() -> String {
        switch jitMethod {
        case .stikdebug:
            return "1. Install StikDebug from App Store\n2. Open StikDebug → Enable JIT\n3. Select GameHub\n4. Return to GameHub"
        case .jitless:
            return "JIT-less mode is active. Performance is reduced."
        case .sideJIT:
            return "1. Run SideJIT server on computer\n2. Connect iPhone via USB\n3. SideJIT enables JIT for GameHub"
        }
    }
}
