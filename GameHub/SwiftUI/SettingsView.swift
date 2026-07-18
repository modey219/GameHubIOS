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
        NavigationStack {
            List {
                Picker("Section", selection: $selectedSection) {
                    ForEach(SettingsSection.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.menu)

                switch selectedSection {
                case .general: generalSettings
                case .graphics: graphicsSettings
                case .audio: audioSettings
                case .input: inputSettings
                case .advanced: advancedSettings
                case .about: aboutSection
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var generalSettings: some View {
        Section("General") {
            Toggle("Show FPS Overlay", isOn: $settingsManager.showFPS)
            Toggle("Haptic Feedback", isOn: $settingsManager.hapticFeedback)
            Stepper("Resolution Scale", value: $settingsManager.resolutionScale, in: 0.5...2.0, step: 0.1)
        }
    }

    private var graphicsSettings: some View {
        Section("Graphics") {
            Picker("GPU Driver", selection: $settingsManager.gpuDriver) {
                ForEach(GraphicsBridge.GPUDriver.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Toggle("DXVK (DX11→Vulkan)", isOn: $settingsManager.useDXVK)
            Toggle("VKD3D (DX12→Vulkan)", isOn: $settingsManager.useVKD3D)
            Toggle("VSync", isOn: $settingsManager.vsync)
            Stepper("Max FPS: \(settingsManager.maxFrameRate)", value: $settingsManager.maxFrameRate, in: 30...120, step: 10)
        }
    }

    private var audioSettings: some View {
        Section("Audio") {
            Picker("Audio Driver", selection: $settingsManager.audioDriver) {
                ForEach(AudioManager.AudioDriver.allCases, id: \.self) { Text($0.displayName).tag($0) }
            }
            Slider(value: $settingsManager.volume, in: 0...1, step: 0.1) {
                Text("Volume: \(Int(settingsManager.volume * 100))%")
            }
        }
    }

    private var inputSettings: some View {
        Section("Input") {
            Toggle("Virtual Gamepad", isOn: $settingsManager.virtualGamepad)
            Toggle("Vibration", isOn: $settingsManager.vibration)
            Picker("Gamepad Type", selection: $settingsManager.gamepadType) {
                Text("Xbox").tag("xbox"); Text("PlayStation").tag("playstation"); Text("Nintendo").tag("nintendo")
            }
            Slider(value: $settingsManager.sensitivity, in: 0.5...2.0, step: 0.1) {
                Text("Sensitivity: \(String(format: "%.1f", settingsManager.sensitivity))x")
            }
        }
    }

    private var advancedSettings: some View {
        Group {
            Section("Box64 Dynarec") {
                Toggle("Enable Dynarec", isOn: $settingsManager.enableDynarec)
                Toggle("Big Block", isOn: $settingsManager.dynarecBigBlock)
                Toggle("Strong Memory", isOn: $settingsManager.dynarecStrongMem)
                Toggle("Safe Flags", isOn: $settingsManager.dynarecSafeFlags)
            }
            Section("Wine") {
                Toggle("ESync", isOn: $settingsManager.wineESync)
                Toggle("FSync", isOn: $settingsManager.wineFSync)
                Toggle("CSMT", isOn: $settingsManager.wineCSMT)
            }
            Section("Data") {
                Button("Export Settings") { exportSettings() }
                Button("Import Settings") { importSettings() }
                Button(role: .destructive) { settingsManager.resetToDefaults() } label: {
                    Label("Reset All Settings", systemImage: "trash")
                }
            }
        }
    }

    private var aboutSection: some View {
        Section("About") {
            HStack { Text("MN emulator"); Spacer(); Text("1.0.0").foregroundColor(.secondary) }
            HStack { Text("Box64"); Spacer(); Text("0.4.0").foregroundColor(.secondary) }
            HStack { Text("Wine"); Spacer(); Text("9.21").foregroundColor(.secondary) }
            HStack { Text("MoltenVK"); Spacer(); Text("1.4.1").foregroundColor(.secondary) }
            HStack { Text("DXVK"); Spacer(); Text("2.6.1").foregroundColor(.secondary) }
            Link("GitHub", destination: URL(string: "https://github.com/modey219/GameHubIOS")!)
            VStack(alignment: .leading, spacing: 4) {
                Text("Created by @R_MOX")
                    .font(.subheadline).bold()
                    .foregroundColor(.blue)
                Text("PC Game Emulator for iPhone & iPad")
                    .font(.caption).foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func exportSettings() {
        let settings: [String: Any] = [
            "darkMode": settingsManager.darkMode,
            "hapticFeedback": settingsManager.hapticFeedback,
            "showFPS": settingsManager.showFPS,
            "resolutionScale": settingsManager.resolutionScale,
            "gpuDriver": settingsManager.gpuDriver.rawValue,
            "useDXVK": settingsManager.useDXVK,
            "useVKD3D": settingsManager.useVKD3D,
            "vsync": settingsManager.vsync,
            "maxFrameRate": settingsManager.maxFrameRate,
            "volume": settingsManager.volume,
            "virtualGamepad": settingsManager.virtualGamepad,
            "enableDynarec": settingsManager.enableDynarec,
            "wineESync": settingsManager.wineESync,
            "wineFSync": settingsManager.wineFSync,
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted) else { return }
        let vc = UIActivityViewController(activityItems: [data], applicationActivities: nil)
        UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
            .flatMap { $0 as? UIWindowScene }
            .flatMap { $0.windows.first }
            .flatMap { $0.rootViewController }?.present(vc, animated: true)
    }

    private func importSettings() {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json], asCopy: true)
        picker.delegate = SettingsImportDelegate.shared
        UIApplication.shared.connectedScenes.first { $0.activationState == .foregroundActive }
            .flatMap { $0 as? UIWindowScene }
            .flatMap { $0.windows.first }
            .flatMap { $0.rootViewController }?.present(picker, animated: true)
    }
}

class SettingsImportDelegate: NSObject, UIDocumentPickerDelegate, ObservableObject {
    static let shared = SettingsImportDelegate()

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first,
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        if let v = json["darkMode"] as? Bool { UserDefaults.standard.set(v, forKey: "darkMode") }
        if let v = json["hapticFeedback"] as? Bool { UserDefaults.standard.set(v, forKey: "hapticFeedback") }
        if let v = json["showFPS"] as? Bool { UserDefaults.standard.set(v, forKey: "showFPS") }
        if let v = json["resolutionScale"] as? Double { UserDefaults.standard.set(v, forKey: "resolutionScale") }
        if let v = json["gpuDriver"] as? String { UserDefaults.standard.set(v, forKey: "gpuDriver") }
        if let v = json["useDXVK"] as? Bool { UserDefaults.standard.set(v, forKey: "useDXVK") }
        if let v = json["useVKD3D"] as? Bool { UserDefaults.standard.set(v, forKey: "useVKD3D") }
        if let v = json["vsync"] as? Bool { UserDefaults.standard.set(v, forKey: "vsync") }
        if let v = json["maxFrameRate"] as? Int { UserDefaults.standard.set(v, forKey: "maxFrameRate") }
        if let v = json["volume"] as? Float { UserDefaults.standard.set(v, forKey: "volume") }
        if let v = json["virtualGamepad"] as? Bool { UserDefaults.standard.set(v, forKey: "virtualGamepad") }
        if let v = json["enableDynarec"] as? Bool { UserDefaults.standard.set(v, forKey: "enableDynarec") }
        if let v = json["wineESync"] as? Bool { UserDefaults.standard.set(v, forKey: "wineESync") }
        if let v = json["wineFSync"] as? Bool { UserDefaults.standard.set(v, forKey: "wineFSync") }
    }
}
