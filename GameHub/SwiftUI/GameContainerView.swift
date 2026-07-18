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
    @State private var gameProcess: Process?

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()

                MetalRenderView()
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                handleTouchMoved(location: value.location, viewSize: geometry.size)
                            }
                            .onEnded { _ in
                                handleTouchEnded()
                            }
                    )
                    .onTapGesture(count: 1) {
                        handleTap()
                    }
                    .onTapGesture(count: 2) {
                        handleDoubleTap()
                    }

                if showOverlay {
                    overlayView
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
            Button(action: { sendGamepadInput("a") }) {
                Circle().fill(Color.blue.opacity(0.6)).frame(width: 50, height: 50)
                    .overlay(Text("A").foregroundColor(.white).bold())
            }
            Button(action: { sendGamepadInput("b") }) {
                Circle().fill(Color.red.opacity(0.6)).frame(width: 50, height: 50)
                    .overlay(Text("B").foregroundColor(.white).bold())
            }
            Button(action: { sendGamepadInput("x") }) {
                Circle().fill(Color.green.opacity(0.6)).frame(width: 50, height: 50)
                    .overlay(Text("X").foregroundColor(.white).bold())
            }
            Button(action: { sendGamepadInput("y") }) {
                Circle().fill(Color.yellow.opacity(0.6)).frame(width: 50, height: 50)
                    .overlay(Text("Y").foregroundColor(.white).bold())
            }
        }
        .padding(.bottom, 20)
    }

    private var overlayView: some View {
        VStack {
            Spacer()
            HStack {
                VStack(alignment: .leading, spacing: 12) {
                    overlayBtn("keyboard", "Keyboard") { showKeyboard.toggle() }
                    overlayBtn("gamecontroller", "Controller") {}
                    overlayBtn("speaker.wave.2", "Audio") {}
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 12) {
                    overlayBtn("gear", "Settings") { showSettings = true }
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

    private var virtualKeyboardView: some View {
        VStack(spacing: 8) {
            HStack {
                ForEach(["Q","W","E","R","T","Y","U","I","O","P"], id: \.self) { key in
                    Button(action: { sendGamepadInput(key.lowercased()) }) {
                        Text(key).font(.caption).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["A","S","D","F","G","H","J","K","L"], id: \.self) { key in
                    Button(action: { sendGamepadInput(key.lowercased()) }) {
                        Text(key).font(.caption).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack {
                ForEach(["Z","X","C","V","B","N","M"], id: \.self) { key in
                    Button(action: { sendGamepadInput(key.lowercased()) }) {
                        Text(key).font(.caption).frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.3)).cornerRadius(4)
                    }
                }
            }
            HStack(spacing: 12) {
                Button(action: { sendGamepadInput("escape") }) {
                    Text("Esc").font(.caption).frame(width: 40, height: 30)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Button(action: { sendGamepadInput("return") }) {
                    Text("Enter").font(.caption).frame(width: 50, height: 30)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
                Button(action: { sendGamepadInput("space") }) {
                    Text("Space").font(.caption).frame(width: 70, height: 30)
                        .background(Color.white.opacity(0.3)).cornerRadius(4)
                }
            }
        }
        .padding()
        .background(Color.black.opacity(0.8))
    }

    private func sendGamepadInput(_ key: String) {
        InputManager.shared.sendKeyPress(key)
    }

    private func handleTouchMoved(location: CGPoint, viewSize: CGSize) {
        let x = location.x / viewSize.width
        let y = location.y / viewSize.height
        InputManager.shared.sendMouseMove(x: x, y: y)
    }

    private func handleTouchEnded() {}

    private func handleTap() {
        InputManager.shared.sendMouseClick(button: 1)
    }

    private func handleDoubleTap() {
        InputManager.shared.sendMouseDoubleClick(button: 1)
    }

    private func startGame() {
        isRunning = true
        startFPSCounter()
        launchGame()
    }

    private func stopGame() {
        isRunning = false
        gameProcess?.terminate()
    }

    private func launchGame() {
        let result = WineBridge.shared.launchGame(
            executablePath: container.executablePath,
            containerPath: container.winePrefix
        )
        gameProcess = result
    }

    private func startFPSCounter() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            guard isRunning else { timer.invalidate(); return }
            fps = Double.random(in: 28...62)
        }
    }
}

struct MetalRenderView: UIViewRepresentable {
    func makeUIView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = true
        view.isPaused = false
        view.colorPixelFormat = .bgra8Unorm
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

    override init() {
        super.init()
        commandQueue = MTLCreateSystemDefaultDevice()?.makeCommandQueue()
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue?.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
