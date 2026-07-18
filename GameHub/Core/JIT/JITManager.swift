import Foundation
import UIKit

class JITManager {
    static let shared = JITManager()

    @Published var isJITEnabled = false
    @Published var jitMethod: JITMethod = .stikdebug
    @Published var jitStatus: JITStatus = .unknown

    enum JITMethod: String, CaseIterable {
        case stikdebug = "stikdebug"
        case jitless = "jitless"
        case sideJIT = "sidejit"
        case trollStore = "trollstore"
        case altJIT = "altjit"

        var displayName: String {
            switch self {
            case .stikdebug: return "StikDebug (Recommended)"
            case .jitless: return "JIT-less Mode"
            case .sideJIT: return "SideJIT"
            case .trollStore: return "TrollStore"
            case .altJIT: return "AltJIT"
            }
        }

        var description: String {
            switch self {
            case .stikdebug: return "Enables JIT via StikDebug. Requires StikDebug app installed."
            case .jitless: return "Run without JIT (slower). Compatible with all devices."
            case .sideJIT: return "Enable JIT via SideJIT server."
            case .trollStore: return "Permanent JIT via TrollStore (requires jailbreak or TrollStore)."
            case .altJIT: return "Alternative JIT enablement method."
            }
        }
    }

    enum JITStatus {
        case unknown
        case enabled
        case disabled
        case error(String)
        case enabling
        case unsupported
    }

    private var jitProcess: Process?
    private var checkTimer: Timer?

    func enableJIT() {
        jitStatus = .enabling

        switch jitMethod {
        case .stikdebug:
            enableViaStikDebug()
        case .jitless:
            enableJITlessMode()
        case .sideJIT:
            enableViaSideJIT()
        case .trollStore:
            enableViaTrollStore()
        case .altJIT:
            enableViaAltJIT()
        }
    }

    private func enableViaStikDebug() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gamehub.ios"

        let stikdebugURL = URL(string: "stikdebug://enable-jit?bundle=\(bundleID)")!

        if UIApplication.shared.canOpenURL(stikdebugURL) {
            UIApplication.shared.open(stikdebugURL) { [weak self] success in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    if success {
                        self?.verifyJIT()
                    } else {
                        self?.jitStatus = .error("Failed to open StikDebug")
                        self?.isJITEnabled = false
                    }
                }
            }
        } else {
            enableViaStikDebugAlternative()
        }
    }

    private func enableViaStikDebugAlternative() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/task_for_pid")
        process.arguments = ["0"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()

            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.checkJITStatus()
            }
        } catch {
            jitStatus = .error("StikDebug not available: \(error.localizedDescription)")
        }
    }

    private func enableViaSideJIT() {
        guard let url = URL(string: "sidejit://enable?pid=\(ProcessInfo.processInfo.processIdentifier)") else {
            jitStatus = .error("Invalid SideJIT URL")
            return
        }

        UIApplication.shared.open(url) { [weak self] success in
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                self?.checkJITStatus()
            }
        }
    }

    private func enableViaTrollStore() {
        jitStatus = .enabled
        isJITEnabled = true
    }

    private func enableViaAltJIT() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.gamehub.ios"

        if let url = URL(string: "altjit://enable?bundle=\(bundleID)") {
            UIApplication.shared.open(url) { [weak self] success in
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    self?.checkJITStatus()
                }
            }
        }
    }

    private func enableJITlessMode() {
        setenv("BOX64_DYNAREC", "0", 1)
        setenv("BOX64_JITLESS", "1", 1)
        jitStatus = .enabled
        isJITEnabled = true
        print("[JIT] Running in JIT-less mode (slower)")
    }

    private func verifyJIT() {
        checkJITStatus()

        if !isJITEnabled {
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
                self?.checkJITStatus()
            }
        }
    }

    private func checkJITStatus() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let result = checkJITEnabled(pid: pid)

        DispatchQueue.main.async {
            self.isJITEnabled = result
            self.jitStatus = result ? .enabled : .disabled
        }
    }

    private func checkJITEnabled(pid: Int32) -> Bool {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]

        let result = sysctl(&mib, 4, &info, &size, nil, 0)
        guard result == 0 else { return false }

        let flags = info.kp_proc.p_flag
        let hasJIT = (flags & P_JIT) != 0
        return hasJIT
    }

    func disableJIT() {
        isJITEnabled = false
        jitStatus = .disabled
        jitProcess?.terminate()
        jitProcess = nil
    }

    func requestJITIfNeeded(completion: @escaping (Bool) -> Void) {
        if isJITEnabled {
            completion(true)
            return
        }

        enableJIT()

        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            completion(self?.isJITEnabled ?? false)
        }
    }

    func getJITInstructions() -> String {
        switch jitMethod {
        case .stikdebug:
            return """
            1. Install StikDebug from the App Store
            2. Open StikDebug and tap "Enable JIT"
            3. Select GameHub from the app list
            4. Wait for JIT to be enabled
            5. Return to GameHub - JIT should now be active
            
            If JIT fails, try restarting both apps.
            """
        case .jitless:
            return """
            JIT-less mode is active.
            Performance will be reduced compared to JIT mode.
            Consider using StikDebug for better performance.
            """
        case .sideJIT:
            return """
            1. Run SideJIT server on your computer
            2. Connect your iPhone via USB
            3. SideJIT will enable JIT for this app
            """
        case .trollStore:
            return """
            TrollStore provides permanent JIT.
            No additional steps needed.
            """
        case .altJIT:
            return """
            1. Install AltJIT on your computer
            2. Connect your iPhone via USB
            3. Run AltJIT and select GameHub
            """
        }
    }
}

import MachO

private let P_JIT: Int32 = 0x0800
private let CTL_KERN: Int32 = 1
private let KERN_PROC: Int32 = 14
private let KERN_PROC_PID: Int32 = 1

private struct kinfo_proc {
    var kp_proc: (p_flag: Int32, p_stat: Int32, p_comm: (Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8, Int8), p_priority: Int32, p_usrpri: Int32, p_nice: Int32, p_estcpu: UInt32, p_slptime: UInt32, p_realtick: UInt32, p_start: (UInt32, UInt32), p_cpticks: Int32, p_ctime: UInt32)
}
