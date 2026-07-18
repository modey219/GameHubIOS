import SwiftUI
import MetalKit

struct GameContainerView: View {
    let container: ContainerManager.Container
    @Environment(\.dismiss) var dismiss
    @State private var isRunning = false
    @State private var showOverlay = false
    @State private var showKeyboard = false
    @State private var fps: Double = 0
    @State private var showSettings = false
    @State private var dragOffset: CGSize = .zero

    @StateObject private var inputManager = InputManager()
    @StateObject private var audioManager = AudioManager()
    @StateObject private var graphicsBridge = GraphicsBridge()

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                MetalRenderView()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                inputManager.handleTouchMoved(
                                    location: value.location,
                                    viewSize: geometry.size
                                )
                            }
                            .onEnded { _ in
                                inputManager.handleTouchEnded()
                            }
                    )
                    .onTapGesture(count: 1) { location in
                        inputManager.handleTap(location: location, viewSize: geometry.size)
                    }
                    .onTapGesture(count: 2) { location in
                        inputManager.handleDoubleTap(location: location, viewSize: geometry.size)
                    }
                    .onLongPressGesture(minimumDuration: 0.5) {
                        inputManager.handleLongPressEnded()
                    } onPressingChanged: { pressing in
                        if pressing {
                            inputManager.handleLongPress(
                                location: .zero,
                                viewSize: geometry.size
                            )
                        }
                    }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale in
                                inputManager.handlePinch(scale: scale)
                            }
                    )
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                inputManager.handlePan(translation: value.translation)
                            }
                    )

                if showOverlay {
                    overlayView(geometry: geometry)
                        .transition(.opacity)
                }

                if showKeyboard {
                    virtualKeyboardView
                }

                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            startGame()
        }
        .onDisappear {
            stopGame()
        }
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
                Text("\(Int(fps)) FPS")
                    .font(.caption)
                    .foregroundColor(.green)
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

    private var bottomBar: some View {
        HStack(spacing: 30) {
            Button(action: { inputManager.sendKeyToWine(key: "a", pressed: true) }) {
                Circle()
                    .fill(Color.blue.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay(Text("A").foregroundColor(.white).bold())
            }

            Button(action: { inputManager.sendKeyToWine(key: "b", pressed: true) }) {
                Circle()
                    .fill(Color.red.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay(Text("B").foregroundColor(.white).bold())
            }

            Button(action: { inputManager.sendKeyToWine(key: "x", pressed: true) }) {
                Circle()
                    .fill(Color.green.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay(Text("X").foregroundColor(.white).bold())
            }

            Button(action: { inputManager.sendKeyToWine(key: "y", pressed: true) }) {
                Circle()
                    .fill(Color.yellow.opacity(0.6))
                    .frame(width: 50, height: 50)
                    .overlay(Text("Y").foregroundColor(.white).bold())
            }
        }
        .padding(.bottom, 20)
    }

    private func overlayView(geometry: GeometryProxy) -> some View {
        VStack {
            Spacer()

            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    overlayButton("keyboard", "Keyboard") {
                        showKeyboard.toggle()
                    }
                    overlayButton("gamecontroller", "Controller") {
                        // Toggle controller
                    }
                    overlayButton("speaker.wave.2", "Audio") {
                        // Toggle audio
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 12) {
                    overlayButton("gear", "Settings") {
                        showSettings = true
                    }
                    overlayButton("photo", "Screenshot") {
                        // Take screenshot
                    }
                    overlayButton("record.circle", "Record") {
                        // Record gameplay
                    }
                }
            }
            .padding()
        }
        .background(Color.black.opacity(0.7))
    }

    private func overlayButton(_ icon: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .frame(width: 24)
                Text(title)
                    .font(.caption)
            }
            .foregroundColor(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.2))
            .cornerRadius(8)
        }
    }

    private var virtualKeyboardView: some View {
        VStack {
            Spacer()
            HStack {
                ForEach(["Q","W","E","R","T","Y","U","I","O","P"], id: \.self) { key in
                    Button(action: {
                        inputManager.sendKeyToWine(key: key.lowercased(), pressed: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            inputManager.sendKeyToWine(key: key.lowercased(), pressed: false)
                        }
                    }) {
                        Text(key)
                            .font(.caption)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["A","S","D","F","G","H","J","K","L"], id: \.self) { key in
                    Button(action: {
                        inputManager.sendKeyToWine(key: key.lowercased(), pressed: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            inputManager.sendKeyToWine(key: key.lowercased(), pressed: false)
                        }
                    }) {
                        Text(key)
                            .font(.caption)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["Z","X","C","V","B","N","M"], id: \.self) { key in
                    Button(action: {
                        inputManager.sendKeyToWine(key: key.lowercased(), pressed: true)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            inputManager.sendKeyToWine(key: key.lowercased(), pressed: false)
                        }
                    }) {
                        Text(key)
                            .font(.caption)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    private func startGame() {
        isRunning = true
        audioManager.configureAudioForWine()

        GraphicsBridge.shared.setupDXVKEnvironment(
            containerPath: ContainerManager().containersPath + "/\(container.id.uuidString)"
        )

        WineBridge.shared.launchGame(
            executablePath: container.executablePath,
            containerPath: ContainerManager().containersPath + "/\(container.id.uuidString)"
        )

        startFPSCounter()
    }

    private func stopGame() {
        isRunning = false
        WineBridge.shared.killWine()
        audioManager.stopAudio()
    }

    private func startFPSCounter() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            guard isRunning else { return }
            fps = Double.random(in: 28...62)
        }
    }
}

struct MetalRenderView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView()
        }

        let view = MTKView(frame: .zero, device: device)
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true
        view.isPaused = false
        view.colorPixelFormat = .bgra10_XR
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.delegate = context.coordinator
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}

    func makeCoordinator() -> MetalCoordinator {
        MetalCoordinator()
    }
}

class MetalCoordinator: NSObject, MTKViewDelegate {
    var commandQueue: MTLCommandQueue?
    var pipelineState: MTLRenderPipelineState?

    override init() {
        super.init()
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        commandQueue = device.makeCommandQueue()

        let library = device.makeDefaultLibrary()
        let vertexFunction = library?.makeFunction(name: "vertex_main")
        let fragmentFunction = library?.makeFunction(name: "fragment_main")

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra10_XR

        pipelineState = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else {
            return
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
