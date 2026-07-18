import Foundation

class SettingsManager: ObservableObject {
    @Published var darkMode: Bool { didSet { save() } }
    @Published var hapticFeedback: Bool { didSet { save() } }
    @Published var showFPS: Bool { didSet { save() } }
    @Published var resolutionScale: Double { didSet { save() } }

    @Published var gpuDriver: GraphicsBridge.GPUDriver { didSet { save() } }
    @Published var useDXVK: Bool { didSet { save() } }
    @Published var useVKD3D: Bool { didSet { save() } }
    @Published var vsync: Bool { didSet { save() } }
    @Published var maxFrameRate: Int { didSet { save() } }

    @Published var audioDriver: AudioManager.AudioDriver { didSet { save() } }
    @Published var volume: Float { didSet { save() } }

    @Published var virtualGamepad: Bool { didSet { save() } }
    @Published var vibration: Bool { didSet { save() } }
    @Published var gamepadType: String { didSet { save() } }
    @Published var sensitivity: Float { didSet { save() } }

    @Published var enableDynarec: Bool { didSet { save() } }
    @Published var dynarecBigBlock: Bool { didSet { save() } }
    @Published var dynarecStrongMem: Bool { didSet { save() } }
    @Published var dynarecSafeFlags: Bool { didSet { save() } }

    @Published var wineESync: Bool { didSet { save() } }
    @Published var wineFSync: Bool { didSet { save() } }
    @Published var wineCSMT: Bool { didSet { save() } }

    init() {
        let d = UserDefaults.standard
        self.darkMode = d.object(forKey: "darkMode") as? Bool ?? false
        self.hapticFeedback = d.object(forKey: "hapticFeedback") as? Bool ?? true
        self.showFPS = d.object(forKey: "showFPS") as? Bool ?? true
        self.resolutionScale = d.object(forKey: "resolutionScale") as? Double ?? 1.0
        self.gpuDriver = GraphicsBridge.GPUDriver(rawValue: d.string(forKey: "gpuDriver") ?? "moltenvk") ?? .moltenVK
        self.useDXVK = d.object(forKey: "useDXVK") as? Bool ?? true
        self.useVKD3D = d.object(forKey: "useVKD3D") as? Bool ?? true
        self.vsync = d.object(forKey: "vsync") as? Bool ?? true
        self.maxFrameRate = d.object(forKey: "maxFrameRate") as? Int ?? 60
        self.audioDriver = AudioManager.AudioDriver(rawValue: d.string(forKey: "audioDriver") ?? "coreaudio") ?? .coreaudio
        self.volume = d.object(forKey: "volume") as? Float ?? 1.0
        self.virtualGamepad = d.object(forKey: "virtualGamepad") as? Bool ?? true
        self.vibration = d.object(forKey: "vibration") as? Bool ?? true
        self.gamepadType = d.string(forKey: "gamepadType") ?? "xbox"
        self.sensitivity = d.object(forKey: "sensitivity") as? Float ?? 1.0
        self.enableDynarec = d.object(forKey: "enableDynarec") as? Bool ?? true
        self.dynarecBigBlock = d.object(forKey: "dynarecBigBlock") as? Bool ?? true
        self.dynarecStrongMem = d.object(forKey: "dynarecStrongMem") as? Bool ?? true
        self.dynarecSafeFlags = d.object(forKey: "dynarecSafeFlags") as? Bool ?? true
        self.wineESync = d.object(forKey: "wineESync") as? Bool ?? true
        self.wineFSync = d.object(forKey: "wineFSync") as? Bool ?? true
        self.wineCSMT = d.object(forKey: "wineCSMT") as? Bool ?? true
    }

    func save() {
        let d = UserDefaults.standard
        d.set(darkMode, forKey: "darkMode")
        d.set(hapticFeedback, forKey: "hapticFeedback")
        d.set(showFPS, forKey: "showFPS")
        d.set(resolutionScale, forKey: "resolutionScale")
        d.set(gpuDriver.rawValue, forKey: "gpuDriver")
        d.set(useDXVK, forKey: "useDXVK")
        d.set(useVKD3D, forKey: "useVKD3D")
        d.set(vsync, forKey: "vsync")
        d.set(maxFrameRate, forKey: "maxFrameRate")
        d.set(audioDriver.rawValue, forKey: "audioDriver")
        d.set(volume, forKey: "volume")
        d.set(virtualGamepad, forKey: "virtualGamepad")
        d.set(vibration, forKey: "vibration")
        d.set(gamepadType, forKey: "gamepadType")
        d.set(sensitivity, forKey: "sensitivity")
        d.set(enableDynarec, forKey: "enableDynarec")
        d.set(dynarecBigBlock, forKey: "dynarecBigBlock")
        d.set(dynarecStrongMem, forKey: "dynarecStrongMem")
        d.set(dynarecSafeFlags, forKey: "dynarecSafeFlags")
        d.set(wineESync, forKey: "wineESync")
        d.set(wineFSync, forKey: "wineFSync")
        d.set(wineCSMT, forKey: "wineCSMT")
    }

    func applySettings() {
        setenv("BOX64_DYNAREC", enableDynarec ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_BIGBLOCK", dynarecBigBlock ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_STRONGMEM", dynarecStrongMem ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_SAFEFLAGS", dynarecSafeFlags ? "1" : "0", 1)
        setenv("WINEESYNC", wineESync ? "1" : "0", 1)
        setenv("WINEFSYNC", wineFSync ? "1" : "0", 1)
        setenv("DXVK_FRAME_RATE", "\(maxFrameRate)", 1)
        setenv("DXVK_HUD", showFPS ? "fps" : "none", 1)
        setenv("DXVK_LOG_LEVEL", "none", 1)
        setenv("MVK_CONFIG_LOG_LEVEL", "0", 1)
        setenv("VKD3D_CONFIG", "dxr", 1)
    }

    func resetToDefaults() {
        let keys = ["darkMode","hapticFeedback","showFPS","resolutionScale",
                     "gpuDriver","useDXVK","useVKD3D","vsync","maxFrameRate",
                     "audioDriver","volume","virtualGamepad","vibration","gamepadType","sensitivity",
                     "enableDynarec","dynarecBigBlock","dynarecStrongMem","dynarecSafeFlags",
                     "wineESync","wineFSync","wineCSMT"]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }
    }
}
