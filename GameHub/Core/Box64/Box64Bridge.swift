import Foundation

class Box64Bridge {
    static let shared = Box64Bridge()

    private var isInitialized = false
    private var box64InstallPath: String = ""

    struct Box64Config {
        var enableDynarec: Bool = true
        var dynarecBigBlock: Bool = true
        var dynarecStrongMem: Bool = true
        var dynarecSafeFlags: Bool = true
        var dynarecAltiVec: Bool = false
        var dynarecCallret: Bool = true
        var dynarecDirty: Bool = true
        var dynarecX8664: Bool = true
        var dynarecX87: Bool = true
        var dynarecFpRound: Bool = true
        var dynarecUnsafeFp: Bool = false
        var box64Debug: Bool = false
        var box64NoBanned: Bool = true
        var box64LD: String = "/usr/lib"
        var box64Path: String = ""
        var winePath: String = ""
        var envVars: [String: String] = [:]
    }

    private var config = Box64Config()

    func initialize() {
        guard !isInitialized else { return }

        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        box64InstallPath = documentsPath.appendingPathComponent("Box64").path

        setupBox64Binary()
        setupEnvironment()
        isInitialized = true
        print("[Box64] Initialized successfully")
    }

    private func setupBox64Binary() {
        let fileManager = FileManager.default
        let box64Dir = URL(fileURLWithPath: box64InstallPath)

        if !fileManager.fileExists(atPath: box64Dir.path) {
            try? fileManager.createDirectory(at: box64Dir, withIntermediateDirectories: true)
        }

        if let bundledBox64 = Bundle.main.path(forResource: "box64", ofType: nil) {
            let destination = box64Dir.appendingPathComponent("box64")
            try? fileManager.removeItem(at: destination)
            try? fileManager.copyItem(atPath: bundledBox64, toPath: destination.path)

            var attrs = try? fileManager.attributesOfItem(atPath: destination.path)
            attrs?[.posixPermissions] = 0o755
            if let attrs = attrs {
                try? fileManager.setAttributes(attrs, ofItemAtPath: destination.path)
            }
        }
    }

    private func setupEnvironment() {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        config.box64Path = documentsPath.appendingPathComponent("Box64").path
        config.winePath = documentsPath.appendingPathComponent("Wine").path

        setenv("BOX64_DYNAREC", config.enableDynarec ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_BIGBLOCK", config.dynarecBigBlock ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_STRONGMEM", config.dynarecStrongMem ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_SAFEFLAGS", config.dynarecSafeFlags ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_CALLRET", config.dynarecCallret ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_DIRTY", config.dynarecDirty ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_X86_64", config.dynarecX8664 ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_X87", config.dynarecX87 ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_FPROUND", config.dynarecFpRound ? "1" : "0", 1)
        setenv("BOX64_NOBANNED", config.box64NoBanned ? "1" : "0", 1)
        setenv("BOX64_LOG", config.box64Debug ? "1" : "0", 1)
        setenv("HOME", config.winePath, 1)

        for (key, value) in config.envVars {
            setenv(key, value, 1)
        }
    }

    func executeX86Binary(path: String, arguments: [String], environment: [String: String]? = nil) -> Int32 {
        guard isInitialized else {
            print("[Box64] Not initialized")
            return -1
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64InstallPath + "/box64")
        process.arguments = [path] + arguments

        var env = ProcessInfo.processInfo.environment
        if let customEnv = environment {
            for (key, value) in customEnv {
                env[key] = value
            }
        }
        process.environment = env

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            print("[Box64] Failed to execute: \(error)")
            return -1
        }
    }

    func executeWithOutput(path: String, arguments: String...) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: box64InstallPath + "/box64")
        process.arguments = [path] + arguments

        do {
            try process.run()
            process.waitUntilExit()
            return (process.terminationStatus, "")
        } catch {
            return (-1, error.localizedDescription)
        }
    }

    func updateConfig(_ updater: (inout Box64Config) -> Void) {
        updater(&config)
        setupEnvironment()
    }

    func getBox64Version() -> String {
        let result = executeWithOutput(path: "", arguments: "--version")
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
