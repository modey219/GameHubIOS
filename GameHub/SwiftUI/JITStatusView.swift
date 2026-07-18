import SwiftUI

struct JITStatusView: View {
    @EnvironmentObject var jitManager: JITManager
    @State private var showInstructions = false

    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                statusCard

                methodPicker

                instructionsButton

                Spacer()
            }
            .padding()
            .navigationTitle("JIT Status")
            .sheet(isPresented: $showInstructions) {
                instructionsSheet
            }
        }
    }

    private var statusCard: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 60))
                .foregroundColor(statusColor)

            Text(statusText)
                .font(.title2)
                .fontWeight(.bold)

            Text(statusDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 20) {
                statusIndicator("CPU", active: jitManager.isJITEnabled)
                statusIndicator("Memory", active: true)
                statusIndicator("GPU", active: true)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JIT Method")
                .font(.headline)

            ForEach(JITManager.JITMethod.allCases, id: \.self) { method in
                Button(action: {
                    jitManager.jitMethod = method
                    jitManager.enableJIT()
                }) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(method.displayName)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.primary)

                            Text(method.description)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }

                        Spacer()

                        if jitManager.jitMethod == method {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.blue)
                        }
                    }
                    .padding(12)
                    .background(
                        jitManager.jitMethod == method ?
                        Color.blue.opacity(0.1) :
                        Color(.systemGray6)
                    )
                    .cornerRadius(10)
                }
            }
        }
    }

    private var instructionsButton: some View {
        Button(action: { showInstructions = true }) {
            Label("Show Setup Instructions", systemImage: "questionmark.circle")
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }

    private var instructionsSheet: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(jitManager.getJITInstructions())
                        .font(.body)
                        .padding()

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Troubleshooting")
                            .font(.headline)

                        troubleshootingTip("JIT fails to enable", "Try restarting both GameHub and StikDebug. Make sure StikDebug has the necessary permissions.")

                        troubleshootingTip("Performance is poor", "JIT is essential for good performance. Without it, Box64 runs in interpreted mode which is ~5-10x slower.")

                        troubleshootingTip("Game crashes", "Try enabling 'Safe Flags' in Box64 settings. Some games require specific Box64 options.")

                        troubleshootingTip("No sound", "Check audio settings and make sure PulseAudio is running. Try switching between audio drivers.")
                    }
                    .padding()
                }
            }
            .navigationTitle("Setup Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { showInstructions = false }
                }
            }
        }
    }

    private func troubleshootingTip(_ title: String, _ description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Q: \(title)")
                .font(.subheadline)
                .fontWeight(.semibold)
            Text("A: \(description)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func statusIndicator(_ name: String, active: Bool) -> some View {
        VStack(spacing: 4) {
            Circle()
                .fill(active ? Color.green : Color.red)
                .frame(width: 8, height: 8)
            Text(name)
                .font(.caption2)
        }
    }

    private var statusIcon: String {
        switch jitManager.jitStatus {
        case .enabled: return "bolt.circle.fill"
        case .disabled: return "bolt.slash.circle"
        case .enabling: return "bolt.circle"
        case .error: return "exclamationmark.triangle.fill"
        case .unknown: return "questionmark.circle"
        case .unsupported: return "xmark.circle"
        }
    }

    private var statusColor: Color {
        switch jitManager.jitStatus {
        case .enabled: return .green
        case .disabled: return .red
        case .enabling: return .yellow
        case .error: return .orange
        case .unknown: return .gray
        case .unsupported: return .red
        }
    }

    private var statusText: String {
        switch jitManager.jitStatus {
        case .enabled: return "JIT Enabled"
        case .disabled: return "JIT Disabled"
        case .enabling: return "Enabling JIT..."
        case .error: return "JIT Error"
        case .unknown: return "JIT Status Unknown"
        case .unsupported: return "JIT Not Supported"
        }
    }

    private var statusDescription: String {
        switch jitManager.jitStatus {
        case .enabled: return "Dynamic recompilation is active. Games will run at full speed."
        case .disabled: return "JIT is not enabled. Performance will be significantly reduced."
        case .enabling: return "Please wait while JIT is being enabled..."
        case .error(let msg): return "Error: \(msg)"
        case .unknown: return "Checking JIT status..."
        case .unsupported: return "JIT is not supported on this device."
        }
    }
}
