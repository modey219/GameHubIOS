import SwiftUI

struct SetupView: View {
    @EnvironmentObject var containerManager: ContainerManager
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @EnvironmentObject var setupManager: SetupManager
    @AppStorage("hasLaunchedBefore") private var hasLaunchedBefore = false

    var body: some View {
        VStack(spacing: 24) {
            ProgressView()
                .scaleEffect(1.5)
            Text(setupManager.statusText)
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .task {
            await runSetup()
        }
    }

    private func runSetup() async {
        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first!
        let box64Path = docs.appendingPathComponent("Box64/box64").path

        if fm.fileExists(atPath: box64Path) {
            hasLaunchedBefore = true
            return
        }

        await MainActor.run { setupManager.statusText = "Extracting Wine..." }
        try? await Task.sleep(nanoseconds: 100_000_000)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    try Box64Bridge.shared.setupAllBundledBinaries { detail in
                        Task { @MainActor in
                            setupManager.statusText = detail
                        }
                    }
                    DispatchQueue.main.async {
                        setupManager.statusText = "Ready"
                        hasLaunchedBefore = true
                        continuation.resume()
                    }
                } catch {
                    DispatchQueue.main.async {
                        setupManager.statusText = "Setup failed: \(error.localizedDescription)"
                        continuation.resume()
                    }
                }
            }
        }
    }
}
