import Foundation
import UIKit

class JITManager: ObservableObject {
    @Published var isJITEnabled = false
    @Published var jitMethod: JITMethod = .jitless
    @Published var jitStatus: JITStatus = .unknown
    @Published var statusMessage: String = ""

    enum JITMethod: String, CaseIterable, Codable {
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
            case .stikdebug: return "Enables JIT via StikDebug app (App Store)"
            case .jitless: return "Run without JIT (slower, but no tools needed)"
            case .sideJIT: return "Enable JIT via SideJIT server on computer"
            }
        }
    }

    enum JITStatus: Equatable {
        case unknown
        case enabled
        case disabled
        case enabling
        case unsupported
        case checking
    }

    private let jitMethodKey = "MNEmulatorJITMethod"

    init() {
        loadMethod()
        checkJITStatus()
    }

    func selectMethod(_ method: JITMethod) {
        jitMethod = method
        saveMethod()
    }

    func enableJIT() {
        jitStatus = .enabling
        statusMessage = "Enabling JIT..."
        switch jitMethod {
        case .stikdebug: enableViaStikDebug()
        case .jitless: enableJITlessMode()
        case .sideJIT: enableViaSideJIT()
        }
    }

    private func enableViaStikDebug() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.mnemulator.ios"
        guard let url = URL(string: "stikdebug://enable-jit?bundle=\(bundleID)") else {
            statusMessage = "Failed to create StikDebug URL"
            jitStatus = .disabled
            return
        }
        if UIApplication.shared.canOpenURL(url) {
            statusMessage = "Opening StikDebug..."
            UIApplication.shared.open(url) { [weak self] success in
                DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                    if success {
                        self?.checkJITStatus()
                        if self?.jitStatus != .enabled {
                            self?.statusMessage = "StikDebug opened. Please tap 'Enable JIT' in StikDebug, then return."
                        }
                    } else {
                        self?.statusMessage = "Failed to open StikDebug"
                        self?.jitStatus = .disabled
                    }
                }
            }
        } else {
            statusMessage = "StikDebug not installed.\nInstall from App Store first."
            jitStatus = .disabled
        }
    }

    private func enableViaSideJIT() {
        let pid = ProcessInfo.processInfo.processIdentifier
        guard let url = URL(string: "sidejit://enable?pid=\(pid)") else {
            statusMessage = "Failed to create SideJIT URL"
            jitStatus = .disabled
            return
        }
        statusMessage = "Opening SideJIT..."
        UIApplication.shared.open(url) { [weak self] success in
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if success {
                    self?.checkJITStatus()
                    if self?.jitStatus != .enabled {
                        self?.statusMessage = "SideJIT opened. Make sure the server is running."
                    }
                } else {
                    self?.statusMessage = "Failed to open SideJIT"
                    self?.jitStatus = .disabled
                }
            }
        }
    }

    func enableJITlessMode() {
        setenv("BOX64_DYNAREC", "0", 1)
        setenv("BOX64_JITLESS", "1", 1)
        DispatchQueue.main.async {
            self.jitStatus = .enabled
            self.isJITEnabled = true
            self.statusMessage = "JIT-less mode active. Performance will be reduced."
        }
    }

    func checkJITStatus() {
        DispatchQueue.main.async {
            self.jitStatus = .checking
        }

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            let dynarec = getenv("BOX64_DYNAREC")
            let dynarecVal = dynarec != nil ? String(cString: dynarec!) : ""

            let jitless = getenv("BOX64_JITLESS")
            let jitlessVal = jitless != nil ? String(cString: jitless!) : ""

            let jitCheck = self.checkSysctlJIT()

            DispatchQueue.main.async {
                if jitlessVal == "1" {
                    self.isJITEnabled = true
                    self.jitStatus = .enabled
                    self.statusMessage = "JIT-less mode active (no dynamic recompilation)"
                } else if jitCheck {
                    self.isJITEnabled = true
                    self.jitStatus = .enabled
                    self.statusMessage = "JIT enabled! Dynamic recompilation active."
                    setenv("BOX64_DYNAREC", "1", 1)
                } else if dynarecVal == "1" {
                    self.isJITEnabled = true
                    self.jitStatus = .enabled
                    self.statusMessage = "Dynarec enabled via environment."
                } else {
                    self.isJITEnabled = false
                    self.jitStatus = .disabled
                    self.statusMessage = "JIT not detected. Use StikDebug or JIT-less mode."
                }
            }
        }
    }

    private func checkSysctlJIT() -> Bool {
        var size: size_t = 0
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]

        let result = sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0)
        guard result == 0 else { return false }

        var info = kinfo_proc()
        var count = Int(size) / MemoryLayout<kinfo_proc>.size
        let sysctlResult = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard sysctlResult == 0 else { return false }

        let flag = info.kp_proc.p_flag
        let P_TRACED: Int32 = 0x00000800
        if (flag & P_TRACED) != 0 {
            return true
        }

        return false
    }

    func getJITInstructions() -> String {
        switch jitMethod {
        case .stikdebug:
            return """
            1. Install StikDebug from the App Store
            2. Open StikDebug on your device
            3. Tap "Enable JIT" and select MN emulator
            4. Return to MN emulator
            5. JIT should now be active
            """
        case .jitless:
            return """
            JIT-less mode is active.

            No external tools needed, but performance
            will be significantly reduced. Games may
            run at 5-20% speed compared to JIT mode.

            Enable JIT via StikDebug for best performance.
            """
        case .sideJIT:
            return """
            1. Install SideJIT server on your computer:
               pip install sidejit
            2. Connect your iPhone via USB cable
            3. Run: sidejit server
            4. SideJIT will enable JIT for this app
            """
        }
    }

    private func saveMethod() {
        UserDefaults.standard.set(jitMethod.rawValue, forKey: jitMethodKey)
    }

    private func loadMethod() {
        guard let raw = UserDefaults.standard.string(forKey: jitMethodKey),
              let method = JITMethod(rawValue: raw) else { return }
        jitMethod = method
    }
}
