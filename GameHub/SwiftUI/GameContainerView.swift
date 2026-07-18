import SwiftUI
import MetalKit
import UIKit

struct GameContainerView: View {
    let container: ContainerManager.Container
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var jitManager: JITManager
    @EnvironmentObject var settingsManager: SettingsManager
    @StateObject private var displayRenderer = DisplayRenderer()
    @State private var isRunning = false
    @State private var showOverlay = false
    @State private var showController = false
    @State private var showKeyboard = false
    @State private var gameProcess: Process?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?
    @State private var errorMessage: String?
    @State private var showError = false
    @State private var wineOutput: String = ""

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black.ignoresSafeArea()

                MetalGameView(renderer: displayRenderer)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { v in
                                let x = Double(v.location.x / geo.size.width * 1920)
                                let y = Double(v.location.y / geo.size.height * 1080)
                                UnixSocketBridge.shared.sendMouseMove(x: x, y: y)
                            }
                            .onEnded { _ in }
                    )
                    .onTapGesture {
                        UnixSocketBridge.shared.handleMouseButton(button: 1, pressed: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            UnixSocketBridge.shared.handleMouseButton(button: 1, pressed: false)
                        }
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        UnixSocketBridge.shared.handleMouseButton(button: 2, pressed: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            UnixSocketBridge.shared.handleMouseButton(button: 2, pressed: false)
                        }
                    }

                VStack {
                    topBar
                    Spacer()
                    if showController { virtualController }
                    if showKeyboard { virtualKeyboard }
                }

                if showOverlay { overlayMenu }
                if showError { errorOverlay }
            }
        }
        .ignoresSafeArea()
        .onAppear { startGame() }
        .onDisappear { stopGame() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark").foregroundColor(.white)
                    .padding(8).background(Color.black.opacity(0.6)).clipShape(Circle())
            }
            Spacer()
            if isRunning {
                HStack(spacing: 8) {
                    Text("\(Int(displayRenderer.fps)) FPS").font(.caption).foregroundColor(.green)
                    Text(formatTime(elapsedTime)).font(.caption).foregroundColor(.yellow)
                }
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.black.opacity(0.6)).cornerRadius(8)
            }
            Button(action: { showOverlay.toggle() }) {
                Image(systemName: "ellipsis.circle").foregroundColor(.white)
                    .padding(8).background(Color.black.opacity(0.6)).clipShape(Circle())
            }
        }
        .padding()
    }

    private var overlayMenu: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    overlayBtn("keyboard", "Keyboard") { withAnimation { showKeyboard.toggle() } }
                    overlayBtn("gamecontroller", "Controller") { withAnimation { showController.toggle() } }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    overlayBtn("doc.text", "Log") {}
                    overlayBtn("photo", "Screenshot") {}
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.7))
    }

    private func overlayBtn(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack { Image(systemName: icon).frame(width: 24); Text(title).font(.caption) }
                .foregroundColor(.white).padding(.horizontal, 16).padding(.vertical, 8)
                .background(Color.white.opacity(0.2)).cornerRadius(8)
        }
    }

    private var errorOverlay: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48)).foregroundColor(.red)
            Text("Game Failed to Launch").font(.headline).foregroundColor(.red)
            ScrollView {
                Text(errorMessage ?? "Unknown error")
                    .font(.caption).foregroundColor(.white)
                    .textSelection(.enabled)
                    .padding()
            }
            .frame(maxHeight: 200)
            .background(Color.black.opacity(0.8))
            .cornerRadius(8)

            HStack {
                Button("Retry") { showError = false; launchGame() }
                    .buttonStyle(.bordered)
                Button("Dismiss") { showError = false; dismiss() }
                    .buttonStyle(.borderedProminent).tint(.red)
            }
        }
        .padding(24)
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(radius: 10)
        .padding(32)
    }

    private var virtualController: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                VStack(spacing: 0) {
                    gamepadBtn("triangle.fill", 0, "dpad_up")
                    HStack(spacing: 0) {
                        gamepadBtn("triangle.fill", -90, "dpad_left")
                        Color.clear.frame(width: 40, height: 30)
                        gamepadBtn("triangle.fill", 90, "dpad_right")
                    }
                    gamepadBtn("triangle.fill", 180, "dpad_down")
                }
                ZStack {
                    actionBtn("Y", "button_y", Color.yellow, offset: (0, -50))
                    actionBtn("X", "button_x", Color.blue, offset: (-50, 0))
                    actionBtn("B", "button_b", Color.red, offset: (50, 0))
                    actionBtn("A", "button_a", Color.green, offset: (0, 50))
                }
            }
            HStack(spacing: 60) {
                analogStick("L", axisX: "leftX", axisY: "leftY")
                analogStick("R", axisX: "rightX", axisY: "rightY")
            }
        }
        .padding()
        .background(Color.black.opacity(0.4))
    }

    private func gamepadBtn(_ icon: String, _ degrees: Double, _ name: String) -> some View {
        Button(action: { sendGamepad(name) }) {
            Image(systemName: icon).rotationEffect(.degrees(degrees))
                .frame(width: 40, height: 30)
                .background(Color.white.opacity(0.3)).cornerRadius(4)
        }
    }

    private func actionBtn(_ label: String, _ name: String, _ color: Color, offset: (CGFloat, CGFloat)) -> some View {
        Button(action: { sendGamepad(name) }) {
            Text(label).font(.caption).bold().frame(width: 44, height: 44)
                .background(color.opacity(0.6)).clipShape(Circle())
        }.offset(x: offset.0, y: offset.1)
    }

    private func analogStick(_ label: String, axisX: String, axisY: String) -> some View {
        VStack {
            Text(label).font(.caption2).foregroundColor(.white)
            ZStack {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 80, height: 80)
                Circle().fill(Color.white.opacity(0.5)).frame(width: 36, height: 36)
                    .gesture(DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            let x = max(-1, min(1, Float(v.location.x / 40 - 1)))
                            let y = max(-1, min(1, Float(v.location.y / 40 - 1)))
                            UnixSocketBridge.shared.handleGamepadAxis(axis: axisX, value: Double(x), player: 0)
                            UnixSocketBridge.shared.handleGamepadAxis(axis: axisY, value: Double(y), player: 0)
                        }
                        .onEnded { _ in
                            UnixSocketBridge.shared.handleGamepadAxis(axis: axisX, value: 0, player: 0)
                            UnixSocketBridge.shared.handleGamepadAxis(axis: axisY, value: 0, player: 0)
                        }
                    )
            }
        }
    }

    private var virtualKeyboard: some View {
        VStack(spacing: 4) {
            ForEach([["Q","W","E","R","T","Y","U","I","O","P"],
                      ["A","S","D","F","G","H","J","K","L"],
                      ["Z","X","C","V","B","N","M"]], id: \.self) { row in
                HStack {
                    ForEach(row, id: \.self) { key in
                        Button(action: { sendKey(key.lowercased()) }) {
                            Text(key).font(.caption2).frame(width: 30, height: 26)
                                .background(Color.white.opacity(0.3)).cornerRadius(4)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                keyBtn("Esc", "escape"); keyBtn("Enter", "return")
                keyBtn("Space", "space"); keyBtn("Tab", "tab")
            }
        }
        .padding().background(Color.black.opacity(0.8))
    }

    private func keyBtn(_ label: String, _ key: String) -> some View {
        Button(action: { sendKey(key) }) {
            Text(label).font(.caption2).frame(width: 40, height: 26)
                .background(Color.white.opacity(0.3)).cornerRadius(4)
        }
    }

    private func sendGamepad(_ name: String) {
        let hash: Int
        switch name {
        case "button_a": hash = 0; case "button_b": hash = 1; case "button_x": hash = 2; case "button_y": hash = 3
        case "dpad_up": hash = 11; case "dpad_down": hash = 12; case "dpad_left": hash = 13; case "dpad_right": hash = 14
        case "start": hash = 6; case "back": hash = 4; case "leftShoulder": hash = 9; case "rightShoulder": hash = 10
        case "leftTrigger": hash = 7; case "rightTrigger": hash = 8
        default: hash = 0
        }
        UnixSocketBridge.shared.handleGamepadButton(button: hash, pressed: true, player: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            UnixSocketBridge.shared.handleGamepadButton(button: hash, pressed: false, player: 0)
        }
    }

    private func sendKey(_ key: String) {
        UnixSocketBridge.shared.handleKeyPress(key: key, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            UnixSocketBridge.shared.handleKeyPress(key: key, pressed: false)
        }
    }

    private func startGame() {
        guard !isRunning else { return }
        isRunning = true
        displayRenderer.startRendering()
        startTimeCounter()
        launchGame()
    }

    private func stopGame() {
        isRunning = false
        displayRenderer.stopRendering()
        timer?.invalidate()
        gameProcess?.terminate()
        gameProcess = nil
        WineBridge.shared.killWine()
        UnixSocketBridge.shared.stopServer()
        AudioBridge.shared.stopAudio()
    }

    private func launchGame() {
        guard !container.executablePath.isEmpty else {
            errorMessage = "No executable path set for this container.\nPlease edit the container and set the .exe path."
            showError = true
            return
        }

        settingsManager.applySettings()

        let fm = FileManager.default
        let docs = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let containerPath = docs.appendingPathComponent("Containers/\(container.id.uuidString)").path

        let box64Path = docs.appendingPathComponent("Box64/box64").path
        let wine64Path = docs.appendingPathComponent("Wine/wine64").path

        guard fm.fileExists(atPath: box64Path) else {
            errorMessage = "Box64 binary not found.\nExpected at: \(box64Path)\n\nPlease transfer Box64 binary via Files app or iTunes File Sharing."
            showError = true
            return
        }
        guard fm.fileExists(atPath: wine64Path) else {
            errorMessage = "Wine binary not found.\nExpected at: \(wine64Path)\n\nPlease transfer Wine binaries via Files app or iTunes File Sharing."
            showError = true
            return
        }

        WinePrefixManager.shared.setupDXVKForContainer(containerPath)
        WinePrefixManager.shared.setupVKD3DForContainer(containerPath)
        WinePrefixManager.shared.setupContainerRegistry(containerPath)

        let driveCPath = containerPath + "/drive_c"
        let gameDir = driveCPath + "/games/\(container.name)"
        let gameExeInDriveC = gameDir + "/" + (container.executablePath as NSString).lastPathComponent

        if !fm.fileExists(atPath: gameDir) {
            try? fm.createDirectory(atPath: gameDir, withIntermediateDirectories: true)
        }

        let sourceExe = container.executablePath
        if fm.fileExists(atPath: sourceExe) && !fm.fileExists(atPath: gameExeInDriveC) {
            try? fm.copyItem(atPath: sourceExe, toPath: gameExeInDriveC)
        }

        let finalExePath: String
        if fm.fileExists(atPath: gameExeInDriveC) {
            finalExePath = "C:\\games\\\(container.name)\\\((container.executablePath as NSString).lastPathComponent)"
        } else {
            finalExePath = container.executablePath
        }

        jitManager.enableJIT()

        let process = Box64Bridge.shared.launchWine(
            wine64Path: wine64Path,
            executablePath: finalExePath,
            containerPath: containerPath,
            environment: container.environment
        )

        if let process = process {
            gameProcess = process
            process.terminationHandler = { proc in
                DispatchQueue.main.async {
                    self.isRunning = false
                    if proc.terminationStatus != 0 {
                        self.errorMessage = "Wine process exited with code \(proc.terminationStatus)\n\nCheck that the .exe path is correct and the game files are in the container."
                        self.showError = true
                    }
                }
            }
        } else {
            errorMessage = "Failed to launch Box64+Wine.\n\nBox64: \(box64Path)\nWine: \(wine64Path)\n\nMake sure both binaries exist and are executable."
            showError = true
        }

        UnixSocketBridge.shared.startServer()
        AudioBridge.shared.startAudioServer()
    }

    private func startTimeCounter() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in elapsedTime += 1 }
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600, m = (Int(t) % 3600) / 60, s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%02d:%02d", m, s)
    }
}

struct MetalGameView: UIViewRepresentable {
    let renderer: DisplayRenderer
    func makeUIView(context: Context) -> MTKView {
        let v = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        v.preferredFramesPerSecond = 60
        v.enableSetNeedsDisplay = false
        v.isPaused = false
        v.colorPixelFormat = .bgra8Unorm
        v.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        v.delegate = context.coordinator
        return v
    }
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.updateTexture(from: renderer)
    }
    func makeCoordinator() -> MetalGameCoordinator { MetalGameCoordinator() }
}

class MetalGameCoordinator: NSObject, MTKViewDelegate {
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    var vertexBuffer: MTLBuffer?
    var texCoordBuffer: MTLBuffer?
    var texture: MTLTexture?
    var samplerState: MTLSamplerState?
    let lock = NSLock()

    let vertexData: [Float] = [-1,-1,0,1, 1,-1,0,1, -1,1,0,1, 1,1,0,1]
    let texCoordData: [Float] = [0,1, 1,1, 0,0, 1,0]

    override init() {
        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        commandQueue = device.makeCommandQueue()

        vertexBuffer = device.makeBuffer(bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: [])
        texCoordBuffer = device.makeBuffer(bytes: texCoordData, length: texCoordData.count * MemoryLayout<Float>.size, options: [])

        guard let library = device.makeDefaultLibrary() else { return }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexShader")
        desc.fragmentFunction = library.makeFunction(name: "fragmentShader")
        desc.colorAttachments[0].pixelFormat = .bgra8Unorm

        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].format = .float4
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[1].format = .float2
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.size * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        vertexDescriptor.layouts[1].stride = MemoryLayout<Float>.size * 2
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stepFunction = .perVertex
        desc.vertexDescriptor = vertexDescriptor

        pipelineState = try? device.makeRenderPipelineState(descriptor: desc)

        let samplerDesc = MTLSamplerDescriptor()
        samplerDesc.minFilter = .linear
        samplerDesc.magFilter = .linear
        samplerDesc.sAddressMode = .clampToEdge
        samplerDesc.tAddressMode = .clampToEdge
        samplerState = device.makeSamplerState(descriptor: samplerDesc)
    }

    func updateTexture(from renderer: DisplayRenderer) {
        guard let newTex = renderer.currentTexture else { return }
        lock.lock()
        texture = newTex
        lock.unlock()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let desc = view.currentRenderPassDescriptor,
              let buf = commandQueue?.makeCommandBuffer(),
              let enc = buf.makeRenderCommandEncoder(descriptor: desc),
              let ps = pipelineState,
              let vb = vertexBuffer,
              let tb = texCoordBuffer,
              let sampler = samplerState else { return }

        lock.lock()
        let tex = texture
        lock.unlock()

        enc.setRenderPipelineState(ps)
        enc.setVertexBuffer(vb, offset: 0, index: 0)
        enc.setVertexBuffer(tb, offset: 0, index: 1)

        if let tex = tex {
            enc.setFragmentTexture(tex, index: 0)
            enc.setFragmentSamplerState(sampler, index: 0)
        }

        enc.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        enc.endEncoding()
        buf.present(drawable)
        buf.commit()
    }
}
