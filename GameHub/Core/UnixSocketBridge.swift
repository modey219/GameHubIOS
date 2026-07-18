import Foundation
import Network

class UnixSocketBridge: ObservableObject {
    static let shared = UnixSocketBridge()

    @Published var isConnected = false
    @Published var inputLatency: Double = 0

    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private var inputQueue = DispatchQueue(label: "com.gamehub.input", qos: .userInteractive)
    private var isServerRunning = false
    private var socketPath: String

    private var mousePosition = CGPoint.zero
    private var mouseButtons: [Int: Bool] = [1: false, 2: false, 3: false]
    private var pressedKeys: Set<String> = []

    struct InputEvent: Codable {
        let type: InputEventType
        let timestamp: Double
        let data: InputData
    }

    enum InputEventType: String, Codable {
        case mouseMove = "mouse_move"
        case mouseButton = "mouse_button"
        case keyPress = "key_press"
        case keyRelease = "key_release"
        case gamepadButton = "gamepad_button"
        case gamepadAxis = "gamepad_axis"
        case touch = "touch"
        case gesture = "gesture"
    }

    struct InputData: Codable {
        var x: Double?
        var y: Double?
        var dx: Double?
        var dy: Double?
        var button: Int?
        var pressed: Bool?
        var key: String?
        var keyCode: Int?
        var value: Double?
        var axis: String?
        var playerIndex: Int?
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        socketPath = docs.appendingPathComponent("Wine/input.sock").path
    }

    func startServer() {
        inputQueue.async { [weak self] in
            guard let self = self else { return }
            self.startPosixServer()
        }
    }

    func stopServer() {
        isServerRunning = false
        if clientSocket >= 0 {
            close(clientSocket)
            clientSocket = -1
        }
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
        }
        try? FileManager.default.removeItem(atPath: socketPath)
        DispatchQueue.main.async {
            self.isConnected = false
        }
    }

    private func startPosixServer() {
        isServerRunning = true

        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            print("[Socket] Failed to create socket")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLen = min(socketPath.count, Int(sizeof(of: addr.sun_path)) - 1)
        socketPath.withCString { cPath in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                let raw = UnsafeMutableRawPointer(ptr)
                _ = raw.copyMemory(from: cPath, byteCount: pathLen)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                bind(serverSocket, sa, addrLen)
            }
        }

        guard bindResult == 0 else {
            print("[Socket] Bind failed: \(errno)")
            close(serverSocket)
            serverSocket = -1
            return
        }

        guard listen(serverSocket, 1) == 0 else {
            print("[Socket] Listen failed")
            close(serverSocket)
            serverSocket = -1
            return
        }

        print("[Socket] Server ready on \(socketPath)")

        while isServerRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    accept(serverSocket, sa, &clientLen)
                }
            }

            if client >= 0 {
                clientSocket = client
                DispatchQueue.main.async {
                    self.isConnected = true
                }
                print("[Socket] Client connected")
                receiveData()
            }
        }
    }

    private func receiveData() {
        let bufferSize = 65536
        var buffer = [UInt8](repeating: 0, count: bufferSize)

        while clientSocket >= 0 && isServerRunning {
            let bytesRead = recv(clientSocket, &buffer, bufferSize, 0)
            if bytesRead > 0 {
                let data = Data(buffer.prefix(bytesRead))
                processInputData(data)
            } else if bytesRead == 0 {
                print("[Socket] Client disconnected")
                DispatchQueue.main.async {
                    self.isConnected = false
                }
                break
            } else {
                if errno != EINTR {
                    print("[Socket] Recv error: \(errno)")
                    break
                }
            }
        }
    }

    private func processInputData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "mouse_move":
            if let x = json["x"] as? Double, let y = json["y"] as? Double {
                handleMouseMove(x: x, y: y)
            }
        case "mouse_button":
            if let button = json["button"] as? Int, let pressed = json["pressed"] as? Bool {
                handleMouseButton(button: button, pressed: pressed)
            }
        case "key_press":
            if let key = json["key"] as? String, let pressed = json["pressed"] as? Bool {
                handleKeyPress(key: key, pressed: pressed)
            }
        case "gamepad_button":
            if let button = json["button"] as? Int, let pressed = json["pressed"] as? Bool,
               let player = json["player"] as? Int {
                handleGamepadButton(button: button, pressed: pressed, player: player)
            }
        case "gamepad_axis":
            if let axis = json["axis"] as? String, let value = json["value"] as? Double,
               let player = json["player"] as? Int {
                handleGamepadAxis(axis: axis, value: value, player: player)
            }
        default:
            break
        }
    }

    func sendMouseMove(x: Double, y: Double) {
        let event = InputEvent(
            type: .mouseMove,
            timestamp: Date().timeIntervalSince1970,
            data: InputData(x: x, y: y)
        )
        sendEvent(event)
    }

    func sendMouseButton(button: Int, pressed: Bool) {
        let event = InputEvent(
            type: .mouseButton,
            timestamp: Date().timeIntervalSince1970,
            data: InputData(button: button, pressed: pressed)
        )
        sendEvent(event)
    }

    func sendKeyPress(_ key: String, pressed: Bool = true) {
        let event = InputEvent(
            type: pressed ? .keyPress : .keyRelease,
            timestamp: Date().timeIntervalSince1970,
            data: InputData(pressed: pressed, key: key)
        )
        sendEvent(event)
    }

    func sendGamepadButton(button: Int, pressed: Bool, player: Int = 0) {
        let event = InputEvent(
            type: .gamepadButton,
            timestamp: Date().timeIntervalSince1970,
            data: InputData(button: button, pressed: pressed, playerIndex: player)
        )
        sendEvent(event)
    }

    func sendGamepadAxis(axis: String, value: Double, player: Int = 0) {
        let event = InputEvent(
            type: .gamepadAxis,
            timestamp: Date().timeIntervalSince1970,
            data: InputData(value: value, axis: axis, playerIndex: player)
        )
        sendEvent(event)
    }

    private func sendEvent(_ event: InputEvent) {
        guard let data = try? JSONEncoder().encode(event) else { return }
        guard clientSocket >= 0 else { return }

        let startTime = Date()

        data.withUnsafeBytes { buffer in
            guard let baseAddress = buffer.baseAddress else { return }
            let sent = send(clientSocket, baseAddress, buffer.count, 0)
            if sent > 0 {
                let latency = Date().timeIntervalSince(startTime)
                DispatchQueue.main.async {
                    self.inputLatency = latency * 1000
                }
            }
        }
    }

    func handleMouseMove(x: CGFloat, y: CGFloat) {
        sendMouseMove(x: Double(x), y: Double(y))
    }

    func handleMouseButton(button: Int, pressed: Bool) {
        sendMouseButton(button: button, pressed: pressed)
    }

    func handleKeyPress(key: String, pressed: Bool) {
        sendKeyPress(key, pressed: pressed)
    }

    func handleGamepadButton(button: Int, pressed: Bool, player: Int) {
        sendGamepadButton(button: button, pressed: pressed, player: player)
    }

    func handleGamepadAxis(axis: String, value: Double, player: Int) {
        sendGamepadAxis(axis: axis, value: value, player: player)
    }
}
