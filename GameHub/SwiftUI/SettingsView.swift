import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedSection: SettingsSection = .general
    @State private var showResetConfirm = false
    @State private var showClearCacheConfirm = false
    @State private var showClearContainersConfirm = false

    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case graphics = "Graphics"
        case audio = "Audio"
        case input = "Input"
        case wine = "Wine"
        case box64 = "Box64"
        case display = "Display"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        List {
                Picker("Section", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)

                switch selectedSection {
                case .general: generalSection
                case .graphics: graphicsSection
                case .audio: audioSection
                case .input: inputSection
                case .wine: wineSection
                case .box64: box64Section
                case .display: displaySection
                case .advanced: advancedSection
                case .about: aboutSection
                }
            }
            .navigationTitle("Settings")
    }

    // MARK: - General
    private var generalSection: some View {
        Group {
            Section("Appearance") {
                Toggle("Dark Mode", isOn: $settingsManager.darkMode)
                Toggle("Keep Screen On", isOn: $settingsManager.keepScreenOn)
            }
            Section("Performance") {
                Toggle("Show FPS Overlay", isOn: $settingsManager.showFPS)
                Picker("Resolution Scale", selection: $settingsManager.resolutionScale) {
                    Text("50%").tag(0.5); Text("75%").tag(0.75)
                    Text("100%").tag(1.0); Text("125%").tag(1.25)
                    Text("150%").tag(1.5); Text("200%").tag(2.0)
                }
                Picker("Memory Limit", selection: $settingsManager.memoryLimitMB) {
                    Text("256 MB (Low)").tag(256)
                    Text("384 MB (Safe)").tag(384)
                    Text("512 MB (Normal)").tag(512)
                    Text("768 MB (High)").tag(768)
                    Text("1024 MB (Max)").tag(1024)
                    Text("Unlimited").tag(0)
                }
                Text("Limits how much RAM Box64+Wine can use. Lower values are safer on devices with less memory.")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Section("Behavior") {
                Toggle("Haptic Feedback", isOn: $settingsManager.hapticFeedback)
                Toggle("Auto-Save State", isOn: $settingsManager.autoSaveState)
                Toggle("Show Touch Buttons", isOn: $settingsManager.showTouchButtons)
            }
            Section("Network") {
                Toggle("Online Mode", isOn: $settingsManager.onlineMode)
                Toggle("Local Multiplayer", isOn: $settingsManager.localMultiplayer)
            }
        }
    }

    // MARK: - Graphics
    private var graphicsSection: some View {
        Group {
            Section("GPU") {
                Picker("GPU Driver", selection: $settingsManager.gpuDriver) {
                    ForEach(GraphicsBridge.GPUDriver.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                Toggle("Force Vulkan", isOn: $settingsManager.forceVulkan)
            }
            Section("Renderers") {
                Toggle("DXVK (DX11 → Vulkan)", isOn: $settingsManager.useDXVK)
                Toggle("VKD3D (DX12 → Vulkan)", isOn: $settingsManager.useVKD3D)
                Toggle("DXVK Async", isOn: $settingsManager.dxvkAsync)
            }
            Section("Sync & Frame Rate") {
                Toggle("VSync", isOn: $settingsManager.vsync)
                Picker("Max FPS", selection: $settingsManager.maxFrameRate) {
                    Text("30").tag(30); Text("45").tag(45); Text("60").tag(60)
                    Text("90").tag(90); Text("120").tag(120); Text("Unlimited").tag(999)
                }
            }
            Section("Quality") {
                Picker("MSAA", selection: $settingsManager.msaaLevel) {
                    Text("Off").tag(0); Text("2x").tag(2); Text("4x").tag(4); Text("8x").tag(8)
                }
                Picker("Anisotropic Filtering", selection: $settingsManager.anisotropicFiltering) {
                    Text("Off").tag(0); Text("2x").tag(2); Text("4x").tag(4)
                    Text("8x").tag(8); Text("16x").tag(16)
                }
                Picker("Texture Quality", selection: $settingsManager.textureQuality) {
                    Text("Low").tag(0); Text("Medium").tag(1); Text("High").tag(2); Text("Ultra").tag(3)
                }
                Picker("Shader Precision", selection: $settingsManager.shaderPrecision) {
                    Text("Low").tag("low"); Text("Medium").tag("medium"); Text("High").tag("high")
                }
            }
            Section("DXVK HUD") {
                Picker("HUD Display", selection: $settingsManager.dxvkHud) {
                    Text("FPS Only").tag("fps")
                    Text("FPS + Frame Time").tag("fps,frametimes")
                    Text("Full (FPS + GPU + Memory)").tag("fps,gpuload,mem")
                    Text("Custom (devinfo,fps,frametimes)").tag("devinfo,fps,frametimes")
                    Text("None").tag("none")
                }
                Picker("MoltenVK Log Level", selection: $settingsManager.mvkLogLevel) {
                    Text("Off").tag(0); Text("Errors").tag(1)
                    Text("Warnings").tag(2); Text("Info").tag(3)
                }
            }
        }
    }

    // MARK: - Audio
    private var audioSection: some View {
        Group {
            Section("General") {
                Toggle("Enable Audio", isOn: $settingsManager.audioEnabled)
                Picker("Audio Driver", selection: $settingsManager.audioDriver) {
                    ForEach(AudioManager.AudioDriver.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
            }
            Section("Output") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Volume")
                        Spacer()
                        Text("\(Int(settingsManager.volume * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.volume, in: 0...1, step: 0.05)
                }
                Picker("Sample Rate", selection: $settingsManager.sampleRate) {
                    Text("22050 Hz").tag(22050); Text("44100 Hz").tag(44100)
                    Text("48000 Hz").tag(48000); Text("96000 Hz").tag(96000)
                }
                Picker("Buffer Count", selection: $settingsManager.audioBufferSize) {
                    Text("2 (Low Latency)").tag(2); Text("4 (Normal)").tag(4)
                    Text("8 (Stable)").tag(8); Text("16 (Safe)").tag(16)
                }
                Picker("Latency Mode", selection: $settingsManager.audioLatency) {
                    Text("Ultra Low").tag("ultra"); Text("Low").tag("low")
                    Text("Normal").tag("normal"); Text("High").tag("high")
                }
            }
        }
    }

    // MARK: - Input
    private var inputSection: some View {
        Group {
            Section("Gamepad") {
                Toggle("Virtual Gamepad", isOn: $settingsManager.virtualGamepad)
                Picker("Gamepad Type", selection: $settingsManager.gamepadType) {
                    Text("Xbox").tag("xbox")
                    Text("PlayStation").tag("playstation")
                    Text("Nintendo Switch").tag("nintendo")
                    Text("Generic PC").tag("generic")
                }
                Toggle("Vibration", isOn: $settingsManager.vibration)
            }
            Section("Analog Sticks") {
                Picker("Stick Mode", selection: $settingsManager.analogStickMode) {
                    Text("Absolute (Direct)").tag("absolute")
                    Text("Relative (Mouse-like)").tag("relative")
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Deadzone")
                        Spacer()
                        Text("\(Int(settingsManager.deadzone * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.deadzone, in: 0...0.5, step: 0.05)
                }
            }
            Section("Touch Input") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Mouse Sensitivity")
                        Spacer()
                        Text(String(format: "%.1fx", settingsManager.sensitivity)).foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.sensitivity, in: 0.5...3.0, step: 0.1)
                }
                VStack(alignment: .leading) {
                    HStack {
                        Text("Touch Sensitivity")
                        Spacer()
                        Text(String(format: "%.1fx", settingsManager.touchSensitivity)).foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.touchSensitivity, in: 0.5...3.0, step: 0.1)
                }
            }
            Section("Virtual Buttons") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Button Opacity")
                        Spacer()
                        Text("\(Int(settingsManager.buttonOpacity * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.buttonOpacity, in: 0.2...1.0, step: 0.05)
                }
            }
        }
    }

    // MARK: - Wine
    private var wineSection: some View {
        Group {
            Section("Performance") {
                Toggle("ESync (Event FD)", isOn: $settingsManager.wineESync)
                Toggle("FSync (Fast Sync)", isOn: $settingsManager.wineFSync)
                Toggle("CSMT (Command Streams)", isOn: $settingsManager.wineCSMT)
                Toggle("Proton Mode", isOn: $settingsManager.protonMode)
            }
            Section("Renderer") {
                Picker("Wine Renderer", selection: $settingsManager.wineRenderer) {
                    Text("Vulkan (Recommended)").tag("vulkan")
                    Text("OpenGL").tag("opengl")
                    Text("GDI (Software)").tag("gdi")
                }
            }
            Section("Debug") {
                Picker("Debug Level", selection: $settingsManager.wineDebugLevel) {
                    Text("None (Silent)").tag("none")
                    Text("Errors Only").tag("+err")
                    Text("Warnings").tag("+warn")
                    Text("All (Verbose)").tag("+all")
                    Text("Channel: relay").tag("+relay")
                    Text("Channel: tid").tag("+tid")
                    Text("Channel: time").tag("+time")
                }
            }
            Section("DLL Overrides") {
                TextField("e.g. d3d11=n,winevulkan=n", text: $settingsManager.wineDllOverrides)
                    .font(.caption)
                    .autocorrectionDisabled()
                Text("Format: dllname=flag (n=native, b=builtin, e=disabled)")
                    .font(.caption2).foregroundColor(.secondary)
            }
            Section("Virtual Desktop") {
                Toggle("Enable Virtual Desktop", isOn: $settingsManager.wineVirtualDesktop)
                if settingsManager.wineVirtualDesktop {
                    Picker("Resolution", selection: $settingsManager.wineVirtualDesktopSize) {
                        Text("1280x720").tag("1280x720")
                        Text("1920x1080").tag("1920x1080")
                        Text("2560x1440").tag("2560x1440")
                        Text("3840x2160").tag("3840x2160")
                    }
                }
            }
        }
    }

    // MARK: - Box64
    private var box64Section: some View {
        Group {
            Section("Dynarec Core") {
                Toggle("Enable Dynarec", isOn: $settingsManager.enableDynarec)
                Toggle("Big Block Mode", isOn: $settingsManager.dynarecBigBlock)
                Toggle("Strong Memory", isOn: $settingsManager.dynarecStrongMem)
                Toggle("Safe Flags", isOn: $settingsManager.dynarecSafeFlags)
            }
            Section("Advanced Dynarec") {
                Picker("AltiVec Level", selection: $settingsManager.dynarecAltiVec) {
                    Text("Disabled").tag(0); Text("Emulate").tag(1); Text("Native").tag(2)
                }
                Toggle("Call/Ret Optimization", isOn: $settingsManager.dynarecCallRet)
                Toggle("Native Flags", isOn: $settingsManager.dynarecNativeFlags)
                Toggle("Restricted Mode", isOn: $settingsManager.dynarecRestricted)
                Toggle("Standard Malloc", isOn: $settingsManager.box64StdMalloc)
            }
            Section("Debug") {
                Picker("Log Level", selection: $settingsManager.dynarecLogLevel) {
                    Text("Off").tag(0); Text("Info").tag(1)
                    Text("Warnings").tag(2); Text("Verbose").tag(3)
                    Text("Debug (Very Verbose)").tag(4)
                }
            }
            Section("Preset Quick Select") {
                Button("Safe (Stable)") {
                    settingsManager.dynarecBigBlock = false
                    settingsManager.dynarecStrongMem = true
                    settingsManager.dynarecSafeFlags = true
                    settingsManager.dynarecCallRet = false
                    settingsManager.dynarecNativeFlags = false
                }
                Button("Balanced") {
                    settingsManager.dynarecBigBlock = true
                    settingsManager.dynarecStrongMem = true
                    settingsManager.dynarecSafeFlags = true
                    settingsManager.dynarecCallRet = true
                    settingsManager.dynarecNativeFlags = true
                }
                Button("Fast (May Crash)") {
                    settingsManager.dynarecBigBlock = true
                    settingsManager.dynarecStrongMem = false
                    settingsManager.dynarecSafeFlags = false
                    settingsManager.dynarecCallRet = true
                    settingsManager.dynarecNativeFlags = true
                }
                Button("Max Performance") {
                    settingsManager.dynarecBigBlock = true
                    settingsManager.dynarecStrongMem = false
                    settingsManager.dynarecSafeFlags = false
                    settingsManager.dynarecCallRet = true
                    settingsManager.dynarecNativeFlags = true
                    settingsManager.dynarecAltiVec = 2
                    settingsManager.dynarecRestricted = false
                }
            }
        }
    }

    // MARK: - Display
    private var displaySection: some View {
        Group {
            Section("Orientation") {
                Toggle("Force Landscape", isOn: $settingsManager.forceLandscape)
                Toggle("Auto Rotate", isOn: $settingsManager.autoRotate)
            }
            Section("Brightness") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Screen Brightness")
                        Spacer()
                        Text("\(Int(settingsManager.brightness * 100))%").foregroundColor(.secondary)
                    }
                    Slider(value: $settingsManager.brightness, in: 0.3...1.0, step: 0.05)
                }
            }
            Section("Overlay") {
                Toggle("Show Controller Button", isOn: $settingsManager.showControllerButton)
            }
        }
    }

    // MARK: - Advanced
    private var advancedSection: some View {
        Group {
            Section("Storage") {
                Button(action: { showClearCacheConfirm = true }) {
                    Label("Clear Shader Cache", systemImage: "trash")
                        .foregroundColor(.orange)
                }
                Button(action: { showClearContainersConfirm = true }) {
                    Label("Clear All Containers", systemImage: "trash")
                        .foregroundColor(.red)
                }
                HStack {
                    Text("Last Backup")
                    Spacer()
                    Text(settingsManager.lastBackupDate).foregroundColor(.secondary)
                }
            }
            Section("Data Management") {
                Button(action: { exportSettings() }) {
                    Label("Export Settings", systemImage: "square.and.arrow.up")
                }
                Button(action: { importSettings() }) {
                    Label("Import Settings", systemImage: "square.and.arrow.down")
                }
            }
            Section("Danger Zone") {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset All Settings to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .alert("Reset All Settings?", isPresented: $showResetConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settingsManager.resetToDefaults()
            }
        } message: {
            Text("This will reset all settings to their default values. This cannot be undone.")
        }
        .alert("Clear Shader Cache?", isPresented: $showClearCacheConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearShaderCache()
            }
        } message: {
            Text("This will remove all compiled shaders. Games may stutter on next launch while recompiling.")
        }
        .alert("Clear All Containers?", isPresented: $showClearContainersConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                clearAllContainers()
            }
        } message: {
            Text("WARNING: This will permanently delete ALL game containers and their data. This cannot be undone!")
        }
    }

    // MARK: - About
    private var aboutSection: some View {
        Group {
            Section("App Info") {
                HStack {
                    Image(systemName: "gamecontroller.fill")
                        .foregroundColor(.purple).frame(width: 28)
                    VStack(alignment: .leading) {
                        Text("MN emulator").font(.headline)
                        Text("PC Game Emulator for iOS").font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("1.0.0").foregroundColor(.secondary)
                }
            }
            Section("Components") {
                HStack { Image(systemName: "cpu").foregroundColor(.blue).frame(width: 28)
                    Text("Box64"); Spacer(); Text("0.4.0").foregroundColor(.secondary) }
                HStack { Image(systemName: "wineglass").foregroundColor(.pink).frame(width: 28)
                    Text("Wine"); Spacer(); Text("9.21").foregroundColor(.secondary) }
                HStack { Image(systemName: "sparkles").foregroundColor(.orange).frame(width: 28)
                    Text("MoltenVK"); Spacer(); Text("1.4.1").foregroundColor(.secondary) }
                HStack { Image(systemName: "bolt.fill").foregroundColor(.yellow).frame(width: 28)
                    Text("DXVK"); Spacer(); Text("2.6.1").foregroundColor(.secondary) }
            }
            Section("Credits") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.circle.fill")
                            .foregroundColor(.purple).frame(width: 28)
                        VStack(alignment: .leading) {
                            Text("Created by @R_MOX").font(.headline)
                            Text("Lead Developer").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    HStack {
                        Image(systemName: "link")
                            .foregroundColor(.blue).frame(width: 28)
                        Link("GitHub Repository", destination: URL(string: "https://github.com/modey219/GameHubIOS")!)
                    }
                }
            }
            Section("Third Party Licenses") {
                Text("Box64 - MIT License").font(.caption)
                Text("Wine - LGPL 2.1").font(.caption)
                Text("MoltenVK - Apache 2.0").font(.caption)
                Text("DXVK - zlib License").font(.caption)
            }
        }
    }

    // MARK: - Helpers
    private func exportSettings() {
        let data = settingsManager.getExportData()
        guard let jsonData = try? JSONSerialization.data(withJSONObject: data, options: .prettyPrinted) else { return }
        let vc = UIActivityViewController(activityItems: [jsonData], applicationActivities: nil)
        topViewController()?.present(vc, animated: true)
    }

    private func importSettings() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = SettingsImportDelegate.shared
        topViewController()?.present(picker, animated: true)
    }

    private func clearShaderCache() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let shaderCache = docs.appendingPathComponent("ShaderCache").path
        try? fm.removeItem(atPath: shaderCache)
    }

    private func clearAllContainers() {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let containers = docs.appendingPathComponent("Containers").path
        try? fm.removeItem(atPath: containers)
    }

    private func topViewController() -> UIViewController? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.rootViewController
    }
}

class SettingsImportDelegate: NSObject, UIDocumentPickerDelegate, ObservableObject {
    static let shared = SettingsImportDelegate()

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        for (key, value) in json {
            UserDefaults.standard.set(value, forKey: key)
        }
        NotificationCenter.default.post(name: .settingsImported, object: nil)
    }
}

extension Notification.Name {
    static let settingsImported = Notification.Name("settingsImported")
}
