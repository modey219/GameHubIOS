import Foundation
import UIKit

class SettingsManager: ObservableObject {

    // MARK: - General
    @Published var darkMode: Bool { didSet { save() } }
    @Published var hapticFeedback: Bool { didSet { save() } }
    @Published var showFPS: Bool { didSet { save() } }
    @Published var resolutionScale: Double { didSet { save() } }
    @Published var keepScreenOn: Bool { didSet { save() } }
    @Published var autoSaveState: Bool { didSet { save() } }
    @Published var showTouchButtons: Bool { didSet { save() } }
    @Published var memoryLimitMB: Int { didSet { save() } }

    // MARK: - Graphics
    @Published var gpuDriver: GraphicsBridge.GPUDriver { didSet { save() } }
    @Published var useDXVK: Bool { didSet { save() } }
    @Published var useVKD3D: Bool { didSet { save() } }
    @Published var vsync: Bool { didSet { save() } }
    @Published var maxFrameRate: Int { didSet { save() } }
    @Published var msaaLevel: Int { didSet { save() } }
    @Published var anisotropicFiltering: Int { didSet { save() } }
    @Published var textureQuality: Int { didSet { save() } }
    @Published var shaderPrecision: String { didSet { save() } }
    @Published var forceVulkan: Bool { didSet { save() } }
    @Published var dxvkAsync: Bool { didSet { save() } }
    @Published var dxvkHud: String { didSet { save() } }
    @Published var mvkLogLevel: Int { didSet { save() } }

    // MARK: - Audio
    @Published var audioDriver: AudioManager.AudioDriver { didSet { save() } }
    @Published var volume: Float { didSet { save() } }
    @Published var sampleRate: Int { didSet { save() } }
    @Published var audioBufferSize: Int { didSet { save() } }
    @Published var audioLatency: String { didSet { save() } }
    @Published var audioEnabled: Bool { didSet { save() } }

    // MARK: - Input
    @Published var virtualGamepad: Bool { didSet { save() } }
    @Published var vibration: Bool { didSet { save() } }
    @Published var gamepadType: String { didSet { save() } }
    @Published var sensitivity: Float { didSet { save() } }
    @Published var deadzone: Float { didSet { save() } }
    @Published var analogStickMode: String { didSet { save() } }
    @Published var touchSensitivity: Float { didSet { save() } }
    @Published var buttonOpacity: Float { didSet { save() } }

    // MARK: - Wine
    @Published var wineESync: Bool { didSet { save() } }
    @Published var wineFSync: Bool { didSet { save() } }
    @Published var wineCSMT: Bool { didSet { save() } }
    @Published var wineDebugLevel: String { didSet { save() } }
    @Published var wineDllOverrides: String { didSet { save() } }
    @Published var wineRenderer: String { didSet { save() } }
    @Published var protonMode: Bool { didSet { save() } }
    @Published var wineVirtualDesktop: Bool { didSet { save() } }
    @Published var wineVirtualDesktopSize: String { didSet { save() } }

    // MARK: - Box64
    @Published var enableDynarec: Bool { didSet { save() } }
    @Published var dynarecBigBlock: Bool { didSet { save() } }
    @Published var dynarecStrongMem: Bool { didSet { save() } }
    @Published var dynarecSafeFlags: Bool { didSet { save() } }
    @Published var dynarecAltiVec: Int { didSet { save() } }
    @Published var dynarecCallRet: Bool { didSet { save() } }
    @Published var dynarecLogLevel: Int { didSet { save() } }
    @Published var dynarecRestricted: Bool { didSet { save() } }
    @Published var dynarecNativeFlags: Bool { didSet { save() } }
    @Published var box64StdMalloc: Bool { didSet { save() } }

    // MARK: - Display
    @Published var forceLandscape: Bool { didSet { save() } }
    @Published var autoRotate: Bool { didSet { save() } }
    @Published var brightness: Float { didSet { save() } }
    @Published var showControllerButton: Bool { didSet { save() } }

    // MARK: - Network
    @Published var onlineMode: Bool { didSet { save() } }
    @Published var localMultiplayer: Bool { didSet { save() } }

    // MARK: - Data
    @Published var lastBackupDate: String { didSet { save() } }

    // MARK: - Init
    init() {
        let d = UserDefaults.standard
        let gi = { (k: String, def: Int) -> Int in (d.object(forKey: k) as? Int) ?? def }
        let gf = { (k: String, def: Float) -> Float in (d.object(forKey: k) as? Float) ?? def }
        let gd = { (k: String, def: Double) -> Double in (d.object(forKey: k) as? Double) ?? def }
        let gb = { (k: String, def: Bool) -> Bool in (d.object(forKey: k) as? Bool) ?? def }
        let gs2 = { (k: String, def: String) -> String in d.string(forKey: k) ?? def }

        // General
        self.darkMode = gb("darkMode", false)
        self.hapticFeedback = gb("hapticFeedback", true)
        self.showFPS = gb("showFPS", true)
        self.resolutionScale = gd("resolutionScale", 1.0)
        self.keepScreenOn = gb("keepScreenOn", true)
        self.autoSaveState = gb("autoSaveState", false)
        self.showTouchButtons = gb("showTouchButtons", true)
        self.memoryLimitMB = gi("memoryLimitMB", 512)

        // Graphics
        self.gpuDriver = GraphicsBridge.GPUDriver(rawValue: gs2("gpuDriver", "moltenvk")) ?? .moltenVK
        self.useDXVK = gb("useDXVK", true)
        self.useVKD3D = gb("useVKD3D", true)
        self.vsync = gb("vsync", true)
        self.maxFrameRate = gi("maxFrameRate", 60)
        self.msaaLevel = gi("msaaLevel", 0)
        self.anisotropicFiltering = gi("anisotropicFiltering", 0)
        self.textureQuality = gi("textureQuality", 2)
        self.shaderPrecision = gs2("shaderPrecision", "high")
        self.forceVulkan = gb("forceVulkan", false)
        self.dxvkAsync = gb("dxvkAsync", true)
        self.dxvkHud = gs2("dxvkHud", "fps")
        self.mvkLogLevel = gi("mvkLogLevel", 0)

        // Audio
        self.audioDriver = AudioManager.AudioDriver(rawValue: gs2("audioDriver", "coreaudio")) ?? .coreaudio
        self.volume = gf("volume", 1.0)
        self.sampleRate = gi("sampleRate", 44100)
        self.audioBufferSize = gi("audioBufferSize", 4)
        self.audioLatency = gs2("audioLatency", "normal")
        self.audioEnabled = gb("audioEnabled", true)

        // Input
        self.virtualGamepad = gb("virtualGamepad", true)
        self.vibration = gb("vibration", true)
        self.gamepadType = gs2("gamepadType", "xbox")
        self.sensitivity = gf("sensitivity", 1.0)
        self.deadzone = gf("deadzone", 0.15)
        self.analogStickMode = gs2("analogStickMode", "absolute")
        self.touchSensitivity = gf("touchSensitivity", 1.0)
        self.buttonOpacity = gf("buttonOpacity", 0.6)

        // Wine
        self.wineESync = gb("wineESync", true)
        self.wineFSync = gb("wineFSync", false)
        self.wineCSMT = gb("wineCSMT", true)
        self.wineDebugLevel = gs2("wineDebugLevel", "none")
        self.wineDllOverrides = gs2("wineDllOverrides", "")
        self.wineRenderer = gs2("wineRenderer", "vulkan")
        self.protonMode = gb("protonMode", false)
        self.wineVirtualDesktop = gb("wineVirtualDesktop", false)
        self.wineVirtualDesktopSize = gs2("wineVirtualDesktopSize", "1920x1080")

        // Box64
        self.enableDynarec = gb("enableDynarec", true)
        self.dynarecBigBlock = gb("dynarecBigBlock", true)
        self.dynarecStrongMem = gb("dynarecStrongMem", true)
        self.dynarecSafeFlags = gb("dynarecSafeFlags", true)
        self.dynarecAltiVec = gi("dynarecAltiVec", 1)
        self.dynarecCallRet = gb("dynarecCallRet", false)
        self.dynarecLogLevel = gi("dynarecLogLevel", 0)
        self.dynarecRestricted = gb("dynarecRestricted", false)
        self.dynarecNativeFlags = gb("dynarecNativeFlags", true)
        self.box64StdMalloc = gb("box64StdMalloc", false)

        // Display
        self.forceLandscape = gb("forceLandscape", true)
        self.autoRotate = gb("autoRotate", false)
        self.brightness = gf("brightness", 1.0)
        self.showControllerButton = gb("showControllerButton", true)

        // Network
        self.onlineMode = gb("onlineMode", false)
        self.localMultiplayer = gb("localMultiplayer", false)

        // Data
        self.lastBackupDate = gs2("lastBackupDate", "Never")
    }

    func save() {
        let d = UserDefaults.standard
        let set = { (k: String, v: Any) in d.set(v, forKey: k) }

        // General
        set("darkMode", darkMode); set("hapticFeedback", hapticFeedback)
        set("showFPS", showFPS); set("resolutionScale", resolutionScale)
        set("keepScreenOn", keepScreenOn); set("autoSaveState", autoSaveState)
        set("showTouchButtons", showTouchButtons); set("memoryLimitMB", memoryLimitMB)

        // Graphics
        set("gpuDriver", gpuDriver.rawValue); set("useDXVK", useDXVK)
        set("useVKD3D", useVKD3D); set("vsync", vsync)
        set("maxFrameRate", maxFrameRate); set("msaaLevel", msaaLevel)
        set("anisotropicFiltering", anisotropicFiltering); set("textureQuality", textureQuality)
        set("shaderPrecision", shaderPrecision); set("forceVulkan", forceVulkan)
        set("dxvkAsync", dxvkAsync); set("dxvkHud", dxvkHud)
        set("mvkLogLevel", mvkLogLevel)

        // Audio
        set("audioDriver", audioDriver.rawValue); set("volume", volume)
        set("sampleRate", sampleRate); set("audioBufferSize", audioBufferSize)
        set("audioLatency", audioLatency); set("audioEnabled", audioEnabled)

        // Input
        set("virtualGamepad", virtualGamepad); set("vibration", vibration)
        set("gamepadType", gamepadType); set("sensitivity", sensitivity)
        set("deadzone", deadzone); set("analogStickMode", analogStickMode)
        set("touchSensitivity", touchSensitivity); set("buttonOpacity", buttonOpacity)

        // Wine
        set("wineESync", wineESync); set("wineFSync", wineFSync)
        set("wineCSMT", wineCSMT); set("wineDebugLevel", wineDebugLevel)
        set("wineDllOverrides", wineDllOverrides); set("wineRenderer", wineRenderer)
        set("protonMode", protonMode); set("wineVirtualDesktop", wineVirtualDesktop)
        set("wineVirtualDesktopSize", wineVirtualDesktopSize)

        // Box64
        set("enableDynarec", enableDynarec); set("dynarecBigBlock", dynarecBigBlock)
        set("dynarecStrongMem", dynarecStrongMem); set("dynarecSafeFlags", dynarecSafeFlags)
        set("dynarecAltiVec", dynarecAltiVec); set("dynarecCallRet", dynarecCallRet)
        set("dynarecLogLevel", dynarecLogLevel); set("dynarecRestricted", dynarecRestricted)
        set("dynarecNativeFlags", dynarecNativeFlags); set("box64StdMalloc", box64StdMalloc)

        // Display
        set("forceLandscape", forceLandscape); set("autoRotate", autoRotate)
        set("brightness", brightness); set("showControllerButton", showControllerButton)

        // Network
        set("onlineMode", onlineMode); set("localMultiplayer", localMultiplayer)

        // Data
        set("lastBackupDate", lastBackupDate)
    }

    func applySettings() {
        // Box64 - DYNAREC disabled (not compiled for iOS)
        setenv("BOX64_DYNAREC", "0", 1)
        setenv("BOX64_LOG", "\(dynarecLogLevel)", 1)
        if box64StdMalloc { setenv("BOX64_STD_MALLOC", "1", 1) }

        // Memory limit (MB) — inform Wine/Box64 via env vars
        let memMB = memoryLimitMB
        setenv("BOX64_MAXMEM", "\(memMB)", 1)
        setenv("WINE_MAX_MEMORY_MB", "\(memMB)", 1)

        // Wine
        setenv("WINEESYNC", wineESync ? "1" : "0", 1)
        setenv("WINEFSYNC", wineFSync ? "1" : "0", 1)
        setenv("WINEDEBUG", wineDebugLevel, 1)
        if !wineDllOverrides.isEmpty {
            setenv("WINEDLLOVERRIDES", wineDllOverrides, 1)
        }
        if wineVirtualDesktop {
            setenv("WINEVIRTUALDESKTOP", "1", 1)
            setenv("WINEDESKTOPSIZE", wineVirtualDesktopSize, 1)
        }

        // DXVK
        setenv("DXVK_FRAME_RATE", "\(maxFrameRate)", 1)
        setenv("DXVK_HUD", dxvkHud, 1)
        setenv("DXVK_LOG_LEVEL", "none", 1)
        setenv("DXVK_ASYNC", dxvkAsync ? "1" : "0", 1)

        // VKD3D
        setenv("VKD3D_CONFIG", "dxr", 1)

        // MoltenVK
        setenv("MVK_CONFIG_LOG_LEVEL", "\(mvkLogLevel)", 1)
        setenv("MVK_CONFIG_SYNCHRONOUS_QUEUE_SUBMITS", "1", 1)

        // Graphics
        if forceVulkan {
            setenv("MESA_VK_DEVICE_SELECT_DEBUG", "1", 1)
        }

        // Audio
        if audioEnabled {
            setenv("PULSE_SERVER", "127.0.0.1", 1)
        }

        // Screen
        if keepScreenOn {
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = true }
        } else {
            DispatchQueue.main.async { UIApplication.shared.isIdleTimerDisabled = false }
        }
    }

    func resetToDefaults() {
        let keys = [
            "darkMode","hapticFeedback","showFPS","resolutionScale","keepScreenOn","autoSaveState","showTouchButtons","memoryLimitMB",
            "gpuDriver","useDXVK","useVKD3D","vsync","maxFrameRate","msaaLevel","anisotropicFiltering",
            "textureQuality","shaderPrecision","forceVulkan","dxvkAsync","dxvkHud","mvkLogLevel",
            "audioDriver","volume","sampleRate","audioBufferSize","audioLatency","audioEnabled",
            "virtualGamepad","vibration","gamepadType","sensitivity","deadzone","analogStickMode",
            "touchSensitivity","buttonOpacity",
            "wineESync","wineFSync","wineCSMT","wineDebugLevel","wineDllOverrides","wineRenderer",
            "protonMode","wineVirtualDesktop","wineVirtualDesktopSize",
            "enableDynarec","dynarecBigBlock","dynarecStrongMem","dynarecSafeFlags","dynarecAltiVec",
            "dynarecCallRet","dynarecLogLevel","dynarecRestricted","dynarecNativeFlags","box64StdMalloc",
            "forceLandscape","autoRotate","brightness","showControllerButton",
            "onlineMode","localMultiplayer","lastBackupDate"
        ]
        for key in keys { UserDefaults.standard.removeObject(forKey: key) }

        darkMode = false; hapticFeedback = true; showFPS = true; resolutionScale = 1.0
        keepScreenOn = true; autoSaveState = false; showTouchButtons = true; memoryLimitMB = 512
        gpuDriver = .moltenVK; useDXVK = true; useVKD3D = true; vsync = true; maxFrameRate = 60
        msaaLevel = 0; anisotropicFiltering = 0; textureQuality = 2; shaderPrecision = "high"
        forceVulkan = false; dxvkAsync = true; dxvkHud = "fps"; mvkLogLevel = 0
        audioDriver = .coreaudio; volume = 1.0; sampleRate = 44100; audioBufferSize = 4
        audioLatency = "normal"; audioEnabled = true
        virtualGamepad = true; vibration = true; gamepadType = "xbox"; sensitivity = 1.0
        deadzone = 0.15; analogStickMode = "absolute"; touchSensitivity = 1.0; buttonOpacity = 0.6
        wineESync = true; wineFSync = false; wineCSMT = true; wineDebugLevel = "none"
        wineDllOverrides = ""; wineRenderer = "vulkan"; protonMode = false
        wineVirtualDesktop = false; wineVirtualDesktopSize = "1920x1080"
        enableDynarec = true; dynarecBigBlock = true; dynarecStrongMem = true; dynarecSafeFlags = true
        dynarecAltiVec = 1; dynarecCallRet = false; dynarecLogLevel = 0; dynarecRestricted = false
        dynarecNativeFlags = true; box64StdMalloc = false
        forceLandscape = true; autoRotate = false; brightness = 1.0; showControllerButton = true
        onlineMode = false; localMultiplayer = false; lastBackupDate = "Never"
    }

    func getExportData() -> [String: Any] {
        var s: [String: Any] = [:]
        let d = UserDefaults.standard
        let keys = [
            "darkMode","hapticFeedback","showFPS","resolutionScale","keepScreenOn","autoSaveState","showTouchButtons","memoryLimitMB",
            "gpuDriver","useDXVK","useVKD3D","vsync","maxFrameRate","msaaLevel","anisotropicFiltering",
            "textureQuality","shaderPrecision","forceVulkan","dxvkAsync","dxvkHud","mvkLogLevel",
            "audioDriver","volume","sampleRate","audioBufferSize","audioLatency","audioEnabled",
            "virtualGamepad","vibration","gamepadType","sensitivity","deadzone","analogStickMode",
            "touchSensitivity","buttonOpacity",
            "wineESync","wineFSync","wineCSMT","wineDebugLevel","wineDllOverrides","wineRenderer",
            "protonMode","wineVirtualDesktop","wineVirtualDesktopSize",
            "enableDynarec","dynarecBigBlock","dynarecStrongMem","dynarecSafeFlags","dynarecAltiVec",
            "dynarecCallRet","dynarecLogLevel","dynarecRestricted","dynarecNativeFlags","box64StdMalloc",
            "forceLandscape","autoRotate","brightness","showControllerButton",
            "onlineMode","localMultiplayer"
        ]
        for key in keys {
            if let v = d.object(forKey: key) { s[key] = v }
        }
        return s
    }

    func importFromData(_ json: [String: Any]) {
        let d = UserDefaults.standard
        for (k, v) in json { d.set(v, forKey: k) }
    }
}
