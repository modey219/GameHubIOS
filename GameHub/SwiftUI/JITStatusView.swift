import SwiftUI

struct JITStatusView: View {
    @EnvironmentObject var jitManager: JITManager
    @State private var showSystemInfo = false
    @State private var memoryUsedMB: Double = 0
    @State private var memoryTimer: Timer?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    statusHeader
                    metricsCard
                    methodPicker
                    instructionsCard
                    Spacer()
                }
                .padding()
            }
            .navigationTitle("JIT Status")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { jitManager.checkJITStatus() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
            .onAppear { startMemoryMonitor() }
            .onDisappear { memoryTimer?.invalidate() }
        }
    }

    private func startMemoryMonitor() {
        memoryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
            updateMemoryUsage()
        }
        updateMemoryUsage()
    }

    private func updateMemoryUsage() {
        memoryUsedMB = 0
    }

    private var statusHeader: some View {
        VStack(spacing: 16) {
            Image(systemName: statusIcon)
                .font(.system(size: 60))
                .foregroundColor(statusColor)
            Text(statusTitle)
                .font(.title2).bold()
            Text(jitManager.statusMessage)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if jitManager.jitStatus == .disabled {
                Button(action: { jitManager.enableJIT() }) {
                    Label("Enable JIT Now", systemImage: "bolt.fill")
                        .fontWeight(.bold)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                }
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
    }

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "chart.bar.fill").foregroundColor(.purple)
                Text("System Metrics").font(.headline)
            }

            let si = jitManager.systemInfo

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                metricBox("Device", value: si.deviceModel, icon: "iphone")
                metricBox("iOS", value: si.iosVersion, icon: "gearshape")
                metricBox("CPU", value: "\(si.cpuCount) cores \(si.cpuType)", icon: "cpu")
                metricBox("RAM Total", value: "\(si.totalMemoryMB) MB", icon: "memorychip")
                metricBox("RAM Used", value: String(format: "%.0f MB", memoryUsedMB), icon: "chart.line.uptrend.xyaxis")
                metricBox("RAM Free", value: "\(si.availableMemoryMB) MB", icon: "cloud")
                metricBox("App Version", value: "\(si.appVersion) (\(si.buildVersion))", icon: "info.circle")
                metricBox("Jailbreak", value: si.jailbreakDetected ? "Detected" : "Not Detected", icon: si.jailbreakDetected ? "exclamationmark.triangle.fill" : "checkmark.shield")
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private func metricBox(_ title: String, value: String, icon: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon).foregroundColor(.blue).font(.caption)
            Text(title).font(.caption2).foregroundColor(.secondary)
            Text(value).font(.caption).bold().lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }

    private var methodPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("JIT Method").font(.headline)
            ForEach(JITManager.JITMethod.allCases, id: \.self) { method in
                Button(action: {
                    jitManager.selectMethod(method)
                    if method == .jitless {
                        jitManager.enableJITlessMode()
                    }
                }) {
                    HStack {
                        Image(systemName: jitManager.jitMethod == method ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(jitManager.jitMethod == method ? .blue : .gray)
                        VStack(alignment: .leading) {
                            Text(method.displayName).font(.subheadline).bold()
                            Text(method.description).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(jitManager.jitMethod == method ? Color.blue.opacity(0.1) : Color(.systemGray6))
                    .cornerRadius(10)
                }
            }
        }
    }

    private var instructionsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "questionmark.circle")
                    .foregroundColor(.blue)
                Text("How to Enable").font(.headline)
            }
            Text(jitManager.getJITInstructions())
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    private var statusIcon: String {
        switch jitManager.jitStatus {
        case .enabled: return "bolt.circle.fill"
        case .disabled: return "bolt.slash.circle"
        case .enabling: return "bolt.circle"
        case .checking: return "arrow.triangle.2.circlepath"
        case .unsupported: return "xmark.octagon.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private var statusColor: Color {
        switch jitManager.jitStatus {
        case .enabled: return .green
        case .disabled: return .red
        case .enabling: return .orange
        case .checking: return .yellow
        case .unsupported: return .red
        case .unknown: return .gray
        }
    }

    private var statusTitle: String {
        switch jitManager.jitStatus {
        case .enabled: return "JIT Enabled"
        case .disabled: return "JIT Disabled"
        case .enabling: return "Enabling JIT..."
        case .checking: return "Checking JIT..."
        case .unsupported: return "JIT Not Supported"
        case .unknown: return "JIT Status Unknown"
        }
    }
}
