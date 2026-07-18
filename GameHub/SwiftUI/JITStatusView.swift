import SwiftUI

struct JITStatusView: View {
    @EnvironmentObject var jitManager: JITManager

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 16) {
                    Image(systemName: jitManager.isJITEnabled ? "bolt.circle.fill" : "bolt.slash.circle")
                        .font(.system(size: 60))
                        .foregroundColor(jitManager.isJITEnabled ? .green : .red)
                    Text(jitManager.isJITEnabled ? "JIT Enabled" : "JIT Disabled")
                        .font(.title2).bold()
                    Text(jitManager.isJITEnabled
                        ? "Dynamic recompilation active. Games will run at full speed."
                        : "Performance will be significantly reduced without JIT.")
                        .font(.subheadline).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .padding(24)
                .background(Color(.systemBackground))
                .cornerRadius(16)
                .shadow(color: .black.opacity(0.1), radius: 8, y: 4)

                VStack(alignment: .leading, spacing: 8) {
                    Text("JIT Method").font(.headline)
                    ForEach(JITManager.JITMethod.allCases, id: \.self) { method in
                        Button(action: { jitManager.jitMethod = method; jitManager.enableJIT() }) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(method.displayName).font(.subheadline).bold()
                                    Text(method.description).font(.caption2).foregroundColor(.secondary).lineLimit(2)
                                }
                                Spacer()
                                if jitManager.jitMethod == method {
                                    Image(systemName: "checkmark.circle.fill").foregroundColor(.blue)
                                }
                            }
                            .padding(12)
                            .background(jitManager.jitMethod == method ? Color.blue.opacity(0.1) : Color(.systemGray6))
                            .cornerRadius(10)
                        }
                    }
                }
                Spacer()
            }
            .padding()
            .navigationTitle("JIT Status")
        }
    }
}
