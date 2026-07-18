import SwiftUI
import MetalKit

struct GameContainerView: View {
    let container: ContainerManager.Container
    @Environment(\.dismiss) var dismiss
    @StateObject private var displayRenderer = DisplayRenderer()
    @ObservedObject private var socketBridge = UnixSocketBridge.shared
    @ObservedObject private var audioBridge = AudioBridge.shared
    @State private var isRunning = false
    @State private var showOverlay = false
    @State private var showKeyboard = false
    @State private var showController = false
    @State private var gameProcess: Process?
    @State private var elapsedTime: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                MetalGameView(renderer: displayRenderer)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleTouchMoved(location: value.location, viewSize: geometry.size)
                            }
                            .onEnded { _ in
                                handleTouchEnded()
                            }
                    )

                if showController {
                    virtualControllerView
                        .transition(.move(edge: .bottom))
                }

                if showOverlay {
                    overlayView
                        .transition(.opacity)
                }

                if showKeyboard {
                    virtualKeyboardView
                        .transition(.move(edge: .bottom))
                }

                VStack {
                    topBar
                    Spacer()
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { startGame() }
        .onDisappear { stopGame() }
    }

    private var topBar: some View {
        HStack {
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
            Spacer()

            if isRunning {
                HStack(spacing: 8) {
                    Text("\(Int(displayRenderer.fps)) FPS")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(formatTime(elapsedTime))
                        .font(.caption)
                        .foregroundColor(.yellow)
                    if socketBridge.isConnected {
                        Image(systemName: "wifi")
                            .foregroundColor(.green)
                            .font(.caption2)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.6))
                .cornerRadius(8)
            }

            Button(action: { showOverlay.toggle() }) {
                Image(systemName: "ellipsis.circle")
                    .foregroundColor(.white)
                    .padding(8)
                    .background(Color.black.opacity(0.6))
                    .clipShape(Circle())
            }
        }
        .padding()
    }

    private var overlayView: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    overlayBtn("keyboard", "Keyboard") {
                        withAnimation { showKeyboard.toggle() }
                    }
                    overlayBtn("gamecontroller", "Controller") {
                        withAnimation { showController.toggle() }
                    }
                    overlayBtn("speaker.wave.2", "Audio") {
                        toggleAudio()
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    overlayBtn("doc.text", "Log") {}
                    overlayBtn("photo", "Screenshot") {}
                    overlayBtn("record.circle", "Record") {}
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.7))
    }

    private func overlayBtn(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon).frame(width: 24)
                Text(title).font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
    }

    private var virtualControllerView: some View {
        VStack(spacing: 16) {
            HStack(spacing: 40) {
                dpadView
                actionButtonsView
            }

            HStack(spacing: 20) {
                triggerView("LT", action: { sendGamepadInput("leftTrigger") })
                triggerView("RT", action: { sendGamepadInput("rightTrigger") })
            }

            HStack(spacing: 60) {
                stickView("L") { x, y in
                    socketBridge.handleGamepadAxis(axis: "leftX", value: Double(x), player: 0)
                    socketBridge.handleGamepadAxis(axis: "leftY", value: Double(y), player: 0)
                }
                stickView("R") { x, y in
                    socketBridge.handleGamepadAxis(axis: "rightX", value: Double(x), player: 0)
                    socketBridge.handleGamepadAxis(axis: "rightY", value: Double(y), player: 0)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.4))
    }

    private var dpadView: some View {
        VStack(spacing: 0) {
            Button(action: { sendGamepadInput("dpad_up") }) {
                Image(systemName: "triangle.fill").rotationEffect(.degrees(0))
                    .frame(width: 40, height: 30)
                    .background(Color.white.opacity(0.3)).cornerRadius(4)
            }
            HStack(spacing: 0) {
                Button(action: { sendGamepadInput("dpad_left") }) {
                    Image(systemName: "triangle.fill").rotationEffect(.degrees(-90))
                        .frame(width: 40, height: 30)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Color.clear.frame(width: 40, height: 30)
                Button(action: { sendGamepadInput("dpad_right") }) {
                    Image(systemName: "triangle.fill").rotationEffect(.degrees(90))
                        .frame(width: 40, height: 30)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
            }
            Button(action: { sendGamepadInput("dpad_down") }) {
                Image(systemName: "triangle.fill").rotationEffect(.degrees(180))
                    .frame(width: 40, height: 30)
                    .background(Color.white.opacity(0.3)).cornerRadius(4)
            }
        }
    }

    private var actionButtonsView: some View {
        ZStack {
            Button(action: { sendGamepadInput("button_y") }) {
                Text("Y").font(.caption).bold()
                    .frame(width: 44, height: 44)
                    .background(Color.yellow.opacity(0.6)).clipShape(Circle())
            }.offset(y: -50)
            Button(action: { sendGamepadInput("button_x") }) {
                Text("X").font(.caption).bold()
                    .frame(width: 44, height: 44)
                    .background(Color.blue.opacity(0.6)).clipShape(Circle())
            }.offset(x: -50)
            Button(action: { sendGamepadInput("button_b") }) {
                Text("B").font(.caption).bold()
                    .frame(width: 44, height: 44)
                    .background(Color.red.opacity(0.6)).clipShape(Circle())
            }.offset(x: 50)
            Button(action: { sendGamepadInput("button_a") }) {
                Text("A").font(.caption).bold()
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.6)).clipShape(Circle())
            }.offset(y: 50)
        }
    }

    private func triggerView(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(.caption2).bold()
                .frame(width: 50, height: 30)
                .background(Color.white.opacity(0.3)).cornerRadius(6)
        }
    }

    private func stickView(_ label: String, onChange: @escaping (Float, Float) -> Void) -> some View {
        VStack {
            Text(label).font(.caption2).foregroundColor(.white)
            ZStack {
                Circle().fill(Color.white.opacity(0.2)).frame(width: 80, height: 80)
                Circle().fill(Color.white.opacity(0.5)).frame(width: 36, height: 36)
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = Float(value.location.x / 80 * 2 - 1)
                                let y = Float(value.location.y / 80 * 2 - 1)
                                onChange(
                                    max(-1, min(1, x)),
                                    max(-1, min(1, y))
                                )
                            }
                            .onEnded { _ in
                                onChange(0, 0)
                            }
                    )
            }
        }
    }

    private var virtualKeyboardView: some View {
        VStack(spacing: 6) {
            HStack {
                ForEach(["Q","W","E","R","T","Y","U","I","O","P"], id: \.self) { key in
                    Button(action: { sendKeyPress(key.lowercased()) }) {
                        Text(key).font(.caption2).frame(width: 30, height: 28)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["A","S","D","F","G","H","J","K","L"], id: \.self) { key in
                    Button(action: { sendKeyPress(key.lowercased()) }) {
                        Text(key).font(.caption2).frame(width: 30, height: 28)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["Z","X","C","V","B","N","M"], id: \.self) { key in
                    Button(action: { sendKeyPress(key.lowercased()) }) {
                        Text(key).font(.caption2).frame(width: 30, height: 28)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack(spacing: 8) {
                Button(action: { sendKeyPress("escape") }) {
                    Text("Esc").font(.caption2).frame(width: 36, height: 28)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Button(action: { sendKeyPress("return") }) {
                    Text("Enter").font(.caption2).frame(width: 44, height: 28)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Button(action: { sendKeyPress("space") }) {
                    Text("Space").font(.caption2).frame(width: 60, height: 28)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Button(action: { sendKeyPress("tab") }) {
                    Text("Tab").font(.caption2).frame(width: 36, height: 28)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    private func sendGamepadInput(_ button: String) {
        socketBridge.handleGamepadButton(button: buttonHash(button), pressed: true, player: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.socketBridge.handleGamepadButton(button: self.buttonHash(button), pressed: false, player: 0)
        }
    }

    private func sendKeyPress(_ key: String) {
        socketBridge.handleKeyPress(key: key, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            self.socketBridge.handleKeyPress(key: key, pressed: false)
        }
    }

    private func buttonHash(_ name: String) -> Int {
        switch name {
        case "button_a": return 0
        case "button_b": return 1
        case "button_x": return 2
        case "button_y": return 3
        case "dpad_up": return 11
        case "dpad_down": return 12
        case "dpad_left": return 13
        case "dpad_right": return 14
        case "start": return 6
        case "back": return 4
        case "leftShoulder": return 9
        case "rightShoulder": return 10
        case "leftTrigger": return 7
        case "rightTrigger": return 8
        default: return 0
        }
    }

    private func handleTouchMoved(location: CGPoint, viewSize: CGSize) {
        let x = Double(location.x / viewSize.width * 1920)
        let y = Double(location.y / viewSize.height * 1080)
        socketBridge.sendMouseMove(x: x, y: y)
    }

    private func handleTouchEnded() {}

    private func handleTap() {
        socketBridge.handleMouseButton(button: 1, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
            self.socketBridge.handleMouseButton(button: 1, pressed: false)
        }
    }

    private func handleLongPress() {
        socketBridge.handleMouseButton(button: 2, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.socketBridge.handleMouseButton(button: 2, pressed: false)
        }
    }

    private func toggleAudio() {
        if audioBridge.isPlaying {
            audioBridge.stopAudio()
        } else {
            audioBridge.startAudioServer()
        }
    }

    private func startGame() {
        isRunning = true
        displayRenderer.startRendering()
        socketBridge.startServer()
        audioBridge.startAudioServer()
        startTimeCounter()
        launchGame()
    }

    private func stopGame() {
        isRunning = false
        displayRenderer.stopRendering()
        socketBridge.stopServer()
        audioBridge.stopAudio()
        timer?.invalidate()
        gameProcess?.terminate()
    }

    private func launchGame() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let containerPath = docs.appendingPathComponent("Containers/\(container.id.uuidString)").path

        WinePrefixManager.shared.setupDXVKForContainer(containerPath)
        WinePrefixManager.shared.setupVKD3DForContainer(containerPath)

        let result = WineBridge.shared.launchGame(
            executablePath: container.executablePath,
            containerPath: containerPath
        )

        gameProcess = result
        gameProcess?.terminationHandler = { proc in
            DispatchQueue.main.async {
                self.isRunning = false
            }
        }
    }

    private func startTimeCounter() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
            elapsedTime += 1
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let hours = Int(time) / 3600
        let minutes = (Int(time) % 3600) / 60
        let seconds = Int(time) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

struct MetalGameView: UIViewRepresentable {
    let renderer: DisplayRenderer

    func makeUIView(context: Context) -> MTKView {
        let device = MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: .zero, device: device)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> MetalGameCoordinator {
        MetalGameCoordinator()
    }
}

class MetalGameCoordinator: NSObject, MTKViewDelegate {
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?
    var texture: MTLTexture?
    var vertexBuffer: MTLBuffer?
    var texCoordBuffer: MTLBuffer?

    let vertexData: [Float] = [
        -1.0, -1.0, 0.0, 1.0,
         1.0, -1.0, 0.0, 1.0,
        -1.0,  1.0, 0.0, 1.0,
         1.0,  1.0, 0.0, 1.0,
    ]

    let texCoordData: [Float] = [
        0.0, 1.0,
        1.0, 1.0,
        0.0, 0.0,
        1.0, 0.0,
    ]

    override init() {
        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else { return }

        commandQueue = device.makeCommandQueue()

        vertexBuffer = device.makeBuffer(
            bytes: vertexData, length: vertexData.count * MemoryLayout<Float>.size, options: []
        )
        texCoordBuffer = device.makeBuffer(
            bytes: texCoordData, length: texCoordData.count * MemoryLayout<Float>.size, options: []
        )

        guard let library = device.makeDefaultLibrary() else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "fragmentShader")
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor),
              let pipelineState = pipelineState,
              let vertexBuffer = vertexBuffer,
              let texCoordBuffer = texCoordBuffer else { return }

        encoder.setRenderPipelineState(pipelineState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(texCoordBuffer, offset: 0, index: 1)

        if let texture = texture {
            encoder.setFragmentTexture(texture, index: 0)
        }

        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
