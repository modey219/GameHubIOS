import Foundation

class UnixSocketBridge: ObservableObject {
    static let shared = UnixSocketBridge()

    @Published var isConnected = false
    @Published var inputLatency: Double = 0

    private var serverSocket: Int32 = -1
    private var clientSocket: Int32 = -1
    private let socketLock = NSLock()
    private var inputQueue = DispatchQueue(label: "com.gamehub.input", qos: .userInteractive)
    private var isServerRunning = false
    private var socketPath: String

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        socketPath = docs.appendingPathComponent("Wine/input.sock").path
    }

    func startServer() {
        inputQueue.async { [weak self] in self?.startPosixServer() }
    }

    func stopServer() {
        isServerRunning = false
        socketLock.lock()
        let cs = clientSocket
        let ss = serverSocket
        clientSocket = -1
        serverSocket = -1
        socketLock.unlock()
        if cs >= 0 { close(cs) }
        if ss >= 0 { close(ss) }
        try? FileManager.default.removeItem(atPath: socketPath)
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func startPosixServer() {
        isServerRunning = true
        unlink(socketPath)

        serverSocket = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverSocket >= 0 else { return }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathLen = min(socketPath.count, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        socketPath.withCString { cPath in
            withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
                UnsafeMutableRawPointer(ptr).copyMemory(from: cPath, byteCount: pathLen)
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(serverSocket, $0, addrLen) }
        }
        guard bindResult == 0 else { close(serverSocket); serverSocket = -1; return }
        guard listen(serverSocket, 1) == 0 else { close(serverSocket); serverSocket = -1; return }

        while isServerRunning {
            var clientAddr = sockaddr_un()
            var clientLen = socklen_t(MemoryLayout<sockaddr_un>.size)
            let client = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { accept(serverSocket, $0, &clientLen) }
            }
            if client >= 0 {
                clientSocket = client
                DispatchQueue.main.async { self.isConnected = true }
                receiveData()
            }
        }
    }

    private func receiveData() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while clientSocket >= 0 && isServerRunning {
            let n = recv(clientSocket, &buffer, buffer.count, 0)
            if n > 0 {
                processInputData(Data(buffer.prefix(n)))
            } else if n == 0 || (n < 0 && errno != EINTR) { break }
        }
        DispatchQueue.main.async { self.isConnected = false }
    }

    private func processInputData(_ data: Data) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }
        switch type {
        case "mouse_move":
            if let x = json["x"] as? Double, let y = json["y"] as? Double { sendMouseMove(x: x, y: y) }
        case "mouse_button":
            if let b = json["button"] as? Int, let p = json["pressed"] as? Bool { sendMouseButton(button: b, pressed: p) }
        case "key_press":
            if let k = json["key"] as? String, let p = json["pressed"] as? Bool { sendKeyPress(k, pressed: p) }
        case "gamepad_button":
            if let b = json["button"] as? Int, let p = json["pressed"] as? Bool, let pl = json["player"] as? Int {
                sendGamepadButton(button: b, pressed: p, player: pl)
            }
        case "gamepad_axis":
            if let a = json["axis"] as? String, let v = json["value"] as? Double, let pl = json["player"] as? Int {
                sendGamepadAxis(axis: a, value: v, player: pl)
            }
        default: break
        }
    }

    func sendMouseMove(x: Double, y: Double) { sendJSON(["type": "mouse_move", "x": x, "y": y]) }
    func sendMouseButton(button: Int, pressed: Bool) { sendJSON(["type": "mouse_button", "button": button, "pressed": pressed]) }
    func sendKeyPress(_ key: String, pressed: Bool = true) { sendJSON(["type": "key_press", "key": key, "pressed": pressed]) }
    func sendGamepadButton(button: Int, pressed: Bool, player: Int = 0) {
        sendJSON(["type": "gamepad_button", "button": button, "pressed": pressed, "player": player])
    }
    func sendGamepadAxis(axis: String, value: Double, player: Int = 0) {
        sendJSON(["type": "gamepad_axis", "axis": axis, "value": value, "player": player])
    }

    func handleMouseMove(x: CGFloat, y: CGFloat) { sendMouseMove(x: Double(x), y: Double(y)) }
    func handleMouseButton(button: Int, pressed: Bool) { sendMouseButton(button: button, pressed: pressed) }
    func handleKeyPress(key: String, pressed: Bool) { sendKeyPress(key, pressed: pressed) }
    func handleGamepadButton(button: Int, pressed: Bool, player: Int) { sendGamepadButton(button: button, pressed: pressed, player: player) }
    func handleGamepadAxis(axis: String, value: Double, player: Int) { sendGamepadAxis(axis: axis, value: value, player: player) }

    private func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
        socketLock.lock()
        let fd = clientSocket
        socketLock.unlock()
        guard fd >= 0 else { return }
        data.withUnsafeBytes { buf in
            if let base = buf.baseAddress { send(fd, base, buf.count, 0) }
        }
    }
}
