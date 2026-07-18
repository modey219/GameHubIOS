import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var settingsManager: SettingsManager
    @State private var selectedSection: SettingsSection = .general

    enum SettingsSection: String, CaseIterable {
        case general = "General"
        case graphics = "Graphics"
        case audio = "Audio"
        case input = "Input"
        case advanced = "Advanced"
        case about = "About"
    }

    var body: some View {
        NavigationView {
            List {
                Picker("Section", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases, id: \.self) { section in
                        Text(section.rawValue).tag(section)
                    }
                }
                .pickerStyle(.menu)

                switch selectedSection {
                case .general:
                    generalSettings
                case .graphics:
                    graphicsSettings
                case .audio:
                    audioSettings
                case .input:
                    inputSettings
                case .advanced:
                    advancedSettings
                case .about:
                    aboutSection
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var generalSettings: some View {
        Section(header: Text("General")) {
            Toggle("Dark Mode", isOn: $settingsManager.darkMode)
            Toggle("Haptic Feedback", isOn: $settingsManager.hapticFeedback)
            Toggle("Show FPS Overlay", isOn: $settingsManager.showFPS)
            Toggle("Auto-save Settings", isOn: $settingsManager.autoSave)

            Stepper("Default Resolution Scale", value: $settingsManager.resolutionScale, in: 0.5...2.0, step: 0.1)
                .textCase(nil)
        }
    }

    private var graphicsSettings: some View {
        Section(header: Text("Graphics")) {
            Picker("GPU Driver", selection: $settingsManager.gpuDriver) {
                ForEach(GraphicsBridge.GPUDriver.allCases, id: \.self) { driver in
                    Text(driver.displayName).tag(driver)
                }
            }

            Toggle("Use DXVK", isOn: $settingsManager.useDXVK)
            Toggle("Use VKD3D", isOn: $settingsManager.useVKD3D)
            Toggle("VSync", isOn: $settingsManager.vsync)
            Toggle("Frame Interpolation", isOn: $settingsManager.frameInterpolation)

            Stepper("Max FPS: \(settingsManager.maxFrameRate)", value: $settingsManager.maxFrameRate, in: 30...120, step: 10)
                .textCase(nil)

            Stepper("MSAA: \(settingsManager.msAA)x", value: $settingsManager.msAA, in: 0...8, step: 2)
                .textCase(nil)

            Stepper("Anisotropic Filtering: \(settingsManager.anisotropicFiltering)x", value: $settingsManager.anisotropicFiltering, in: 1...16, step: 2)
                .textCase(nil)
        }
    }

    private var audioSettings: some View {
        Section(header: Text("Audio")) {
            Picker("Audio Driver", selection: $settingsManager.audioDriver) {
                ForEach(AudioManager.AudioDriver.allCases, id: \.self) { driver in
                    Text(driver.displayName).tag(driver)
                }
            }

            Slider(value: $settingsManager.volume, in: 0...1, step: 0.1) {
                Text("Volume: \(Int(settingsManager.volume * 100))%")
            }

            Stepper("Audio Buffer: \(settingsManager.audioBufferSize) samples", value: $settingsManager.audioBufferSize, in: 256...4096, step: 256)
                .textCase(nil)
        }
    }

    private var inputSettings: some View {
        Section(header: Text("Input")) {
            Toggle("Virtual Gamepad", isOn: $settingsManager.virtualGamepad)
            Toggle("Enable Vibration", isOn: $settingsManager.vibration)

            Picker("Gamepad Type", selection: $settingsManager.gamepadType) {
                Text("Xbox").tag("xbox")
                Text("PlayStation").tag("playstation")
                Text("Nintendo").tag("nintendo")
            }

            Slider(value: $settingsManager.sensitivity, in: 0.5...2.0, step: 0.1) {
                Text("Sensitivity: \(String(format: "%.1f", settingsManager.sensitivity))x")
            }

            Slider(value: $settingsManager.deadzone, in: 0...0.5, step: 0.05) {
                Text("Deadzone: \(String(format: "%.2f", settingsManager.deadzone))")
            }
        }
    }

    private var advancedSettings: some View {
        Section(header: Text("Box64")) {
            Toggle("Dynarec (JIT)", isOn: $settingsManager.enableDynarec)
            Toggle("Big Block", isOn: $settingsManager.dynarecBigBlock)
            Toggle("Strong Memory", isOn: $settingsManager.dynarecStrongMem)
            Toggle("Safe Flags", isOn: $settingsManager.dynarecSafeFlags)
            Toggle("Call/Ret Optimization", isOn: $settingsManager.dynarecCallRet)
            Toggle("Dirty Optimization", isOn: $settingsManager.dynarecDirty)
        }

        Section(header: Text("Wine")) {
            Toggle("ESync", isOn: $settingsManager.wineESync)
            Toggle("FSync", isOn: $settingsManager.wineFSync)
            Toggle("CSMT", isOn: $settingsManager.wineCSMT)

            Picker("Debug Channels", selection: $settingsManager.wineDebugChannels) {
                Text("Off").tag("")
                Text("All").tag("+all")
                Text("WineD3D").tag("+wined3d")
                Text("Vulkan").tag("+vulkan")
                Text("Sound").tag("+sound")
            }
        }

        Section(header: Text("Data")) {
            Button(action: exportSettings) {
                Label("Export Settings", systemImage: "square.and.arrow.up")
            }
            Button(action: importSettings) {
                Label("Import Settings", systemImage: "square.and.arrow.down")
            }
            Button(action: resetSettings, role: .destructive) {
                Label("Reset All Settings", systemImage: "trash")
            }
        }
    }

    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("GameHub iOS")
                    .font(.headline)
                Spacer()
                Text("1.0.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Box64")
                    .font(.subheadline)
                Spacer()
                Text("0.4.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("Wine")
                    .font(.subheadline)
                Spacer()
                Text("9.0")
                    .foregroundColor(.secondary)
            }

            HStack {
                Text("MoltenVK")
                    .font(.subheadline)
                Spacer()
                Text("1.2.5")
                    .foregroundColor(.secondary)
            }

            Link("GitHub Repository", destination: URL(string: "https://github.com/gamehub-ios")!)
        }
    }

    private func exportSettings() {
        let defaults = UserDefaults.standard
        guard let data = try? JSONSerialization.data(withJSONObject: defaults.dictionaryRepresentation(), options: .prettyPrinted) else { return }
        let activityVC = UIActivityViewController(activityItems: [data], applicationActivities: nil)
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(activityVC, animated: true)
        }
    }

    private func importSettings() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json])
        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let root = scene.windows.first?.rootViewController {
            root.present(picker, animated: true)
        }
    }

    private func resetSettings() {
        settingsManager.resetToDefaults()
    }
}
