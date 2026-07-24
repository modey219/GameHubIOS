import SwiftUI
import UIKit

func swiftLog(_ msg: String) {
    let ts = ISO8601DateFormatter().string(from: Date())
    let line = "[\(ts)] \(msg)\n"
    guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
    let path = docs.appendingPathComponent("app_flow.log").path
    if let fh = FileHandle(forWritingAtPath: path) {
        fh.seekToEndOfFile()
        if let data = line.data(using: .utf8) { fh.write(data) }
        fh.closeFile()
    } else {
        FileManager.default.createFile(atPath: path, contents: line.data(using: .utf8))
    }
}

@main
struct GameHubApp: App {
    @StateObject private var containerManager = ContainerManager()
    @StateObject private var jitManager = JITManager()
    @StateObject private var settingsManager = SettingsManager()

    var body: some Scene {
        WindowGroup {
            RootView(containerManager: containerManager, jitManager: jitManager, settingsManager: settingsManager)
        }
    }
}

struct RootView: View {
    @ObservedObject var containerManager: ContainerManager
    @ObservedObject var jitManager: JITManager
    @ObservedObject var settingsManager: SettingsManager
    @State private var showContent = false

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            if showContent {
                ContentView()
                    .environmentObject(containerManager)
                    .environmentObject(jitManager)
                    .environmentObject(settingsManager)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "gamecontroller.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                    Text("MN emulator").font(.largeTitle).bold()
                    Text("PC Game Emulator for iPhone & iPad").font(.subheadline).foregroundColor(.secondary)
                    Text("Created by @R_MOX").font(.caption).foregroundColor(.secondary)
                    ProgressView().scaleEffect(1.2)
                }
                .onAppear { swiftLog("Splash appeared") }
            }
        }
        .onAppear {
            swiftLog("RootView.onAppear: setting showContent=true")
            showContent = true
        }
    }
}
