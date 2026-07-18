import Foundation

class SettingsManager: ObservableObject {
    @Published var darkMode: Bool {
        didSet { save() }
    }
    @Published var hapticFeedback: Bool {
        didSet { save() }
    }
    @Published var showFPS: Bool {
        didSet { save() }
    }
    @Published var autoSave: Bool {
        didSet { save() }
    }
    @Published var resolutionScale: Double {
        didSet { save() }
    }

    @Published var gpuDriver: GraphicsBridge.GPUDriver {
        didSet { save() }
    }
    @Published var useDXVK: Bool {
        didSet { save() }
    }
    @Published var useVKD3D: Bool {
        didSet { save() }
    }
    @Published var vsync: Bool {
        didSet { save() }
    }
    @Published var frameInterpolation: Bool {
        didSet { save() }
    }
    @Published var maxFrameRate: Int {
        didSet { save() }
    }
    @Published var msAA: Int {
        didSet { save() }
    }
    @Published var anisotropicFiltering: Int {
        didSet { save() }
    }

    @Published var audioDriver: AudioManager.AudioDriver {
        didSet { save() }
    }
    @Published var volume: Float {
        didSet { save() }
    }
    @Published var audioBufferSize: Int {
        didSet { save() }
    }

    @Published var virtualGamepad: Bool {
        didSet { save() }
    }
    @Published var vibration: Bool {
        didSet { save() }
    }
    @Published var gamepadType: String {
        didSet { save() }
    }
    @Published var sensitivity: Float {
        didSet { save() }
    }
    @Published var deadzone: Float {
        didSet { save() }
    }

    @Published var enableDynarec: Bool {
        didSet { save() }
    }
    @Published var dynarecBigBlock: Bool {
        didSet { save() }
    }
    @Published var dynarecStrongMem: Bool {
        didSet { save() }
    }
    @Published var dynarecSafeFlags: Bool {
        didSet { save() }
    }
    @Published var dynarecCallRet: Bool {
        didSet { save() }
    }
    @Published var dynarecDirty: Bool {
        didSet { save() }
    }

    @Published var wineESync: Bool {
        didSet { save() }
    }
    @Published var wineFSync: Bool {
        didSet { save() }
    }
    @Published var wineCSMT: Bool {
        didSet { save() }
    }
    @Published var wineDebugChannels: String {
        didSet { save() }
    }

    private let settingsKey = "GameHubSettings"

    init() {
        let defaults = UserDefaults.standard

        self.darkMode = defaults.bool(forKey: "darkMode")
        self.hapticFeedback = defaults.object(forKey: "hapticFeedback") as? Bool ?? true
        self.showFPS = defaults.object(forKey: "showFPS") as? Bool ?? true
        self.autoSave = defaults.object(forKey: "autoSave") as? Bool ?? true
        self.resolutionScale = defaults.double(forKey: "resolutionScale") != 0 ? defaults.double(forKey: "resolutionScale") : 1.0

        self.gpuDriver = GraphicsBridge.GPUDriver(rawValue: defaults.string(forKey: "gpuDriver") ?? "moltenvk") ?? .moltenVK
        self.useDXVK = defaults.object(forKey: "useDXVK") as? Bool ?? true
        self.useVKD3D = defaults.object(forKey: "useVKD3D") as? Bool ?? true
        self.vsync = defaults.object(forKey: "vsync") as? Bool ?? true
        self.frameInterpolation = defaults.object(forKey: "frameInterpolation") as? Bool ?? false
        self.maxFrameRate = defaults.integer(forKey: "maxFrameRate") != 0 ? defaults.integer(forKey: "maxFrameRate") : 60
        self.msAA = defaults.integer(forKey: "msAA") != 0 ? defaults.integer(forKey: "msAA") : 0
        self.anisotropicFiltering = defaults.integer(forKey: "anisotropicFiltering") != 0 ? defaults.integer(forKey: "anisotropicFiltering") : 4

        self.audioDriver = AudioManager.AudioDriver(rawValue: defaults.string(forKey: "audioDriver") ?? "pulseaudio") ?? .pulseaudio
        self.volume = defaults.object(forKey: "volume") as? Float ?? 1.0
        self.audioBufferSize = defaults.integer(forKey: "audioBufferSize") != 0 ? defaults.integer(forKey: "audioBufferSize") : 1024

        self.virtualGamepad = defaults.object(forKey: "virtualGamepad") as? Bool ?? true
        self.vibration = defaults.object(forKey: "vibration") as? Bool ?? true
        self.gamepadType = defaults.string(forKey: "gamepadType") ?? "xbox"
        self.sensitivity = defaults.object(forKey: "sensitivity") as? Float ?? 1.0
        self.deadzone = defaults.object(forKey: "deadzone") as? Float ?? 0.15

        self.enableDynarec = defaults.object(forKey: "enableDynarec") as? Bool ?? true
        self.dynarecBigBlock = defaults.object(forKey: "dynarecBigBlock") as? Bool ?? true
        self.dynarecStrongMem = defaults.object(forKey: "dynarecStrongMem") as? Bool ?? true
        self.dynarecSafeFlags = defaults.object(forKey: "dynarecSafeFlags") as? Bool ?? true
        self.dynarecCallRet = defaults.object(forKey: "dynarecCallRet") as? Bool ?? true
        self.dynarecDirty = defaults.object(forKey: "dynarecDirty") as? Bool ?? true

        self.wineESync = defaults.object(forKey: "wineESync") as? Bool ?? true
        self.wineFSync = defaults.object(forKey: "wineFSync") as? Bool ?? true
        self.wineCSMT = defaults.object(forKey: "wineCSMT") as? Bool ?? true
        self.wineDebugChannels = defaults.string(forKey: "wineDebugChannels") ?? ""
    }

    func save() {
        let defaults = UserDefaults.standard

        defaults.set(darkMode, forKey: "darkMode")
        defaults.set(hapticFeedback, forKey: "hapticFeedback")
        defaults.set(showFPS, forKey: "showFPS")
        defaults.set(autoSave, forKey: "autoSave")
        defaults.set(resolutionScale, forKey: "resolutionScale")

        defaults.set(gpuDriver.rawValue, forKey: "gpuDriver")
        defaults.set(useDXVK, forKey: "useDXVK")
        defaults.set(useVKD3D, forKey: "useVKD3D")
        defaults.set(vsync, forKey: "vsync")
        defaults.set(frameInterpolation, forKey: "frameInterpolation")
        defaults.set(maxFrameRate, forKey: "maxFrameRate")
        defaults.set(msAA, forKey: "msAA")
        defaults.set(anisotropicFiltering, forKey: "anisotropicFiltering")

        defaults.set(audioDriver.rawValue, forKey: "audioDriver")
        defaults.set(volume, forKey: "volume")
        defaults.set(audioBufferSize, forKey: "audioBufferSize")

        defaults.set(virtualGamepad, forKey: "virtualGamepad")
        defaults.set(vibration, forKey: "vibration")
        defaults.set(gamepadType, forKey: "gamepadType")
        defaults.set(sensitivity, forKey: "sensitivity")
        defaults.set(deadzone, forKey: "deadzone")

        defaults.set(enableDynarec, forKey: "enableDynarec")
        defaults.set(dynarecBigBlock, forKey: "dynarecBigBlock")
        defaults.set(dynarecStrongMem, forKey: "dynarecStrongMem")
        defaults.set(dynarecSafeFlags, forKey: "dynarecSafeFlags")
        defaults.set(dynarecCallRet, forKey: "dynarecCallRet")
        defaults.set(dynarecDirty, forKey: "dynarecDirty")

        defaults.set(wineESync, forKey: "wineESync")
        defaults.set(wineFSync, forKey: "wineFSync")
        defaults.set(wineCSMT, forKey: "wineCSMT")
        defaults.set(wineDebugChannels, forKey: "wineDebugChannels")

        applySettings()
    }

    func applySettings() {
        setenv("BOX64_DYNAREC", enableDynarec ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_BIGBLOCK", dynarecBigBlock ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_STRONGMEM", dynarecStrongMem ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_SAFEFLAGS", dynarecSafeFlags ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_CALLRET", dynarecCallRet ? "1" : "0", 1)
        setenv("BOX64_DYNAREC_DIRTY", dynarecDirty ? "1" : "0", 1)

        setenv("WINE_ESYNC", wineESync ? "1" : "0", 1)
        setenv("WINE_FSYNC", wineFSync ? "1" : "0", 1)
        setenv("WINE_CSMT", wineCSMT ? "1" : "0", 1)
        setenv("WINE_DEBUG", wineDebugChannels, 1)

        setenv("DXVK_FRAME_RATE", "\(maxFrameRate)", 1)
        setenv("DXVK_HUD", showFPS ? "fps" : "none", 1)
    }

    func resetToDefaults() {
        let defaults = UserDefaults.dictionaryRepresentation()
        for key in defaults.keys {
            UserDefaults.standard.removeObject(forKey: key)
        }

        darkMode = false
        hapticFeedback = true
        showFPS = true
        autoSave = true
        resolutionScale = 1.0
        gpuDriver = .moltenVK
        useDXVK = true
        useVKD3D = true
        vsync = true
        frameInterpolation = false
        maxFrameRate = 60
        msAA = 0
        anisotropicFiltering = 4
        audioDriver = .pulseaudio
        volume = 1.0
        audioBufferSize = 1024
        virtualGamepad = true
        vibration = true
        gamepadType = "xbox"
        sensitivity = 1.0
        deadzone = 0.15
        enableDynarec = true
        dynarecBigBlock = true
        dynarecStrongMem = true
        dynarecSafeFlags = true
        dynarecCallRet = true
        dynarecDirty = true
        wineESync = true
        wineFSync = true
        wineCSMT = true
        wineDebugChannels = ""
    }
}

extension SettingsManager: Codable {
    enum CodingKeys: String, CodingKey {
        case darkMode, hapticFeedback, showFPS, autoSave, resolutionScale
        case gpuDriver, useDXVK, useVKD3D, vsync, frameInterpolation, maxFrameRate, msAA, anisotropicFiltering
        case audioDriver, volume, audioBufferSize
        case virtualGamepad, vibration, gamepadType, sensitivity, deadzone
        case enableDynarec, dynarecBigBlock, dynarecStrongMem, dynarecSafeFlags, dynarecCallRet, dynarecDirty
        case wineESync, wineFSync, wineCSMT, wineDebugChannels
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(darkMode, forKey: .darkMode)
        try container.encode(hapticFeedback, forKey: .hapticFeedback)
        try container.encode(showFPS, forKey: .showFPS)
        try container.encode(autoSave, forKey: .autoSave)
        try container.encode(resolutionScale, forKey: .resolutionScale)
        try container.encode(gpuDriver.rawValue, forKey: .gpuDriver)
        try container.encode(useDXVK, forKey: .useDXVK)
        try container.encode(useVKD3D, forKey: .useVKD3D)
        try container.encode(vsync, forKey: .vsync)
        try container.encode(frameInterpolation, forKey: .frameInterpolation)
        try container.encode(maxFrameRate, forKey: .maxFrameRate)
        try container.encode(msAA, forKey: .msAA)
        try container.encode(anisotropicFiltering, forKey: .anisotropicFiltering)
        try container.encode(audioDriver.rawValue, forKey: .audioDriver)
        try container.encode(volume, forKey: .volume)
        try container.encode(audioBufferSize, forKey: .audioBufferSize)
        try container.encode(virtualGamepad, forKey: .virtualGamepad)
        try container.encode(vibration, forKey: .vibration)
        try container.encode(gamepadType, forKey: .gamepadType)
        try container.encode(sensitivity, forKey: .sensitivity)
        try container.encode(deadzone, forKey: .deadzone)
        try container.encode(enableDynarec, forKey: .enableDynarec)
        try container.encode(dynarecBigBlock, forKey: .dynarecBigBlock)
        try container.encode(dynarecStrongMem, forKey: .dynarecStrongMem)
        try container.encode(dynarecSafeFlags, forKey: .dynarecSafeFlags)
        try container.encode(dynarecCallRet, forKey: .dynarecCallRet)
        try container.encode(dynarecDirty, forKey: .dynarecDirty)
        try container.encode(wineESync, forKey: .wineESync)
        try container.encode(wineFSync, forKey: .wineFSync)
        try container.encode(wineCSMT, forKey: .wineCSMT)
        try container.encode(wineDebugChannels, forKey: .wineDebugChannels)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        darkMode = try container.decode(Bool.self, forKey: .darkMode)
        hapticFeedback = try container.decode(Bool.self, forKey: .hapticFeedback)
        showFPS = try container.decode(Bool.self, forKey: .showFPS)
        autoSave = try container.decode(Bool.self, forKey: .autoSave)
        resolutionScale = try container.decode(Double.self, forKey: .resolutionScale)
        gpuDriver = GraphicsBridge.GPUDriver(rawValue: try container.decode(String.self, forKey: .gpuDriver)) ?? .moltenVK
        useDXVK = try container.decode(Bool.self, forKey: .useDXVK)
        useVKD3D = try container.decode(Bool.self, forKey: .useVKD3D)
        vsync = try container.decode(Bool.self, forKey: .vsync)
        frameInterpolation = try container.decode(Bool.self, forKey: .frameInterpolation)
        maxFrameRate = try container.decode(Int.self, forKey: .maxFrameRate)
        msAA = try container.decode(Int.self, forKey: .msAA)
        anisotropicFiltering = try container.decode(Int.self, forKey: .anisotropicFiltering)
        audioDriver = AudioManager.AudioDriver(rawValue: try container.decode(String.self, forKey: .audioDriver)) ?? .pulseaudio
        volume = try container.decode(Float.self, forKey: .volume)
        audioBufferSize = try container.decode(Int.self, forKey: .audioBufferSize)
        virtualGamepad = try container.decode(Bool.self, forKey: .virtualGamepad)
        vibration = try container.decode(Bool.self, forKey: .vibration)
        gamepadType = try container.decode(String.self, forKey: .gamepadType)
        sensitivity = try container.decode(Float.self, forKey: .sensitivity)
        deadzone = try container.decode(Float.self, forKey: .deadzone)
        enableDynarec = try container.decode(Bool.self, forKey: .enableDynarec)
        dynarecBigBlock = try container.decode(Bool.self, forKey: .dynarecBigBlock)
        dynarecStrongMem = try container.decode(Bool.self, forKey: .dynarecStrongMem)
        dynarecSafeFlags = try container.decode(Bool.self, forKey: .dynarecSafeFlags)
        dynarecCallRet = try container.decode(Bool.self, forKey: .dynarecCallRet)
        dynarecDirty = try container.decode(Bool.self, forKey: .dynarecDirty)
        wineESync = try container.decode(Bool.self, forKey: .wineESync)
        wineFSync = try container.decode(Bool.self, forKey: .wineFSync)
        wineCSMT = try container.decode(Bool.self, forKey: .wineCSMT)
        wineDebugChannels = try container.decode(String.self, forKey: .wineDebugChannels)
    }
}
