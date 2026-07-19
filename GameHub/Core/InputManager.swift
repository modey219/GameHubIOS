import Foundation
import UIKit
import GameController

class InputManager: ObservableObject {
    static let shared = InputManager()
    @Published var connectedControllers: [GCController] = []
    @Published var activeProfile: InputProfile?
    @Published var isTouchscreenActive = false
    @Published var isKeyboardVisible = false

    struct InputProfile: Codable, Identifiable {
        var id = UUID()
        var name: String
        var buttonMappings: [ButtonMapping]
        var axisMappings: [AxisMapping]
        var touchScreenMapping: [TouchMapping]

        struct ButtonMapping: Codable {
            var gamepadButton: String
            var keyboardKey: String
            var mouseButton: Int?
            var holdDuration: Double = 0
        }

        struct AxisMapping: Codable {
            var gamepadAxis: String
            var mouseAxis: String
            var sensitivity: Float = 1.0
            var deadzone: Float = 0.15
            var invertY: Bool = false
        }

        struct TouchMapping: Codable {
            var region: CGRect
            var action: String
            var keyboardKey: String?
            var mouseButton: Int?
            var gamepadButton: String?
        }
    }

    private var mousePosition: CGPoint = .zero
    private var rightStickCenter: CGPoint = .zero

    private let inputSocketPath: String = {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return docs.appendingPathComponent("Containers/input.sock").path
    }()

    init() {
        setupControllerObserver()
        loadDefaultProfile()
    }

    private func setupControllerObserver() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerConnected),
            name: .GCControllerDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect, object: nil
        )
        GCController.startWirelessControllerDiscovery {}
    }

    @objc private func controllerConnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        DispatchQueue.main.async {
            self.connectedControllers.append(controller)
            self.setupControllerInputs(controller: controller)
        }
    }

    @objc private func controllerDisconnected(_ notification: Notification) {
        guard let controller = notification.object as? GCController else { return }
        DispatchQueue.main.async {
            self.connectedControllers.removeAll { $0 == controller }
        }
    }

    private func setupControllerInputs(controller: GCController) {
        controller.extendedGamepad?.valueChangedHandler = { [weak self] gamepad, element in
            self?.handleGamepadInput(gamepad: gamepad, element: element)
        }
    }

    private func handleGamepadInput(gamepad: GCExtendedGamepad, element: GCControllerElement) {
        guard let _ = activeProfile else { return }

        if element == gamepad.leftThumbstick {
            let x = gamepad.leftThumbstick.xAxis.value
            let y = gamepad.leftThumbstick.yAxis.value
            handleLeftStick(x: x, y: y)
        }

        if element == gamepad.rightThumbstick {
            let x = gamepad.rightThumbstick.xAxis.value
            let y = gamepad.rightThumbstick.yAxis.value
            handleRightStick(x: x, y: y)
        }

        let buttonMap: [(GCControllerButtonInput, String)] = [
            (gamepad.buttonA, "a"), (gamepad.buttonB, "b"),
            (gamepad.buttonX, "x"), (gamepad.buttonY, "y"),
        ]
        for (btn, name) in buttonMap {
            if element == btn {
                handleButtonPress(button: name, pressed: btn.isPressed)
            }
        }

        if element == gamepad.leftTrigger {
            handleTrigger(value: gamepad.leftTrigger.value, trigger: "left")
        }
        if element == gamepad.rightTrigger {
            handleTrigger(value: gamepad.rightTrigger.value, trigger: "right")
        }
    }

    private func handleLeftStick(x: Float, y: Float) {
        let deadzone: Float = 0.15
        let adjustedX = abs(x) > deadzone ? x : 0
        let adjustedY = abs(y) > deadzone ? y : 0

        sendKeyPress("w", pressed: adjustedY > 0.5)
        sendKeyPress("s", pressed: adjustedY < -0.5)
        sendKeyPress("a", pressed: adjustedX < -0.5)
        sendKeyPress("d", pressed: adjustedX > 0.5)
    }

    private func handleRightStick(x: Float, y: Float) {
        let sensitivity: Float = 10.0
        let deltaX = x * sensitivity
        let deltaY = y * sensitivity
        if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 {
            sendMouseMove(x: mousePosition.x + CGFloat(deltaX), y: mousePosition.y + CGFloat(deltaY))
        }
    }

    private func handleButtonPress(button: String, pressed: Bool) {
        guard let profile = activeProfile else { return }
        if let mapping = profile.buttonMappings.first(where: { $0.gamepadButton == button }) {
            sendKeyPress(mapping.keyboardKey, pressed: pressed)
        }
    }

    private func handleTrigger(value: Float, trigger: String) {
        let btn = trigger == "left" ? 1 : 0
        if value > 0.5 {
            sendMouseButton(btn, pressed: true)
        } else {
            sendMouseButton(btn, pressed: false)
        }
    }

    func sendKeyPress(_ key: String, pressed: Bool = true) {
        let input: [String: Any] = [
            "type": "key",
            "key": key,
            "pressed": pressed,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendInputToWine(input)
    }

    func sendMouseMove(x: CGFloat, y: CGFloat) {
        mousePosition = CGPoint(x: x, y: y)
        let input: [String: Any] = [
            "type": "mouse_move",
            "x": Double(x),
            "y": Double(y),
            "timestamp": Date().timeIntervalSince1970
        ]
        sendInputToWine(input)
    }

    func sendMouseButton(_ button: Int, pressed: Bool) {
        let input: [String: Any] = [
            "type": "mouse_button",
            "button": button,
            "pressed": pressed,
            "timestamp": Date().timeIntervalSince1970
        ]
        sendInputToWine(input)
    }

    func sendMouseClick(button: Int = 1) {
        sendMouseButton(button, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.sendMouseButton(button, pressed: false)
        }
    }

    func sendMouseDoubleClick(button: Int = 1) {
        sendMouseClick(button: button)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.sendMouseClick(button: button)
        }
    }

    private func sendInputToWine(_ input: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: input) else { return }

        let inputDir = (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("Wine/input")
        try? FileManager.default.createDirectory(at: inputDir, withIntermediateDirectories: true)

        let inputFile = inputDir.appendingPathComponent("input_\(Int(Date().timeIntervalSince1970 * 1000)).json")
        try? data.write(to: inputFile)

        let fm = FileManager.default
        let existing = (try? fm.contentsOfDirectory(atPath: inputDir.path)) ?? []
        if existing.count > 100 {
            let sorted = existing.sorted()
            for old in sorted.prefix(existing.count - 50) {
                try? fm.removeItem(atPath: inputDir.appendingPathComponent(old).path)
            }
        }
    }

    func handleTouchBegan(location: CGPoint, viewSize: CGSize) {
        isTouchscreenActive = true
        let scaledX = location.x / viewSize.width * 1920
        let scaledY = location.y / viewSize.height * 1080
        sendMouseMove(x: scaledX, y: scaledY)
    }

    func handleTouchMoved(location: CGPoint, viewSize: CGSize) {
        let scaledX = location.x / viewSize.width * 1920
        let scaledY = location.y / viewSize.height * 1080
        sendMouseMove(x: scaledX, y: scaledY)
    }

    func handleTouchEnded() {
        isTouchscreenActive = false
    }

    func handleLongPress(location: CGPoint, viewSize: CGSize) {
        sendMouseButton(2, pressed: true)
    }

    func handleLongPressEnded() {
        sendMouseButton(2, pressed: false)
    }

    func handlePinch(scale: CGFloat) {
        sendKeyPress("plus", pressed: true)
        sendKeyPress("plus", pressed: false)
    }

    func handlePan(translation: CGPoint) {
        sendMouseMove(x: mousePosition.x + translation.x * 2, y: mousePosition.y + translation.y * 2)
    }

    func toggleKeyboard() {
        isKeyboardVisible.toggle()
    }

    func sendTextInput(_ text: String) {
        for char in text {
            sendKeyPress(String(char), pressed: true)
            sendKeyPress(String(char), pressed: false)
        }
    }

    func loadDefaultProfile() {
        activeProfile = InputProfile(
            name: "Default Xbox",
            buttonMappings: [
                InputProfile.ButtonMapping(gamepadButton: "a", keyboardKey: "space"),
                InputProfile.ButtonMapping(gamepadButton: "b", keyboardKey: "Escape"),
                InputProfile.ButtonMapping(gamepadButton: "x", keyboardKey: "e"),
                InputProfile.ButtonMapping(gamepadButton: "y", keyboardKey: "f"),
                InputProfile.ButtonMapping(gamepadButton: "start", keyboardKey: "Return"),
                InputProfile.ButtonMapping(gamepadButton: "select", keyboardKey: "Escape"),
                InputProfile.ButtonMapping(gamepadButton: "leftShoulder", keyboardKey: "Tab"),
                InputProfile.ButtonMapping(gamepadButton: "rightShoulder", keyboardKey: "BackSpace"),
            ],
            axisMappings: [
                InputProfile.AxisMapping(gamepadAxis: "leftX", mouseAxis: "none"),
                InputProfile.AxisMapping(gamepadAxis: "leftY", mouseAxis: "none"),
                InputProfile.AxisMapping(gamepadAxis: "rightX", mouseAxis: "x", sensitivity: 10.0),
                InputProfile.AxisMapping(gamepadAxis: "rightY", mouseAxis: "y", sensitivity: 10.0),
            ],
            touchScreenMapping: []
        )
    }

    func loadProfile(_ profile: InputProfile) { activeProfile = profile }

    func saveProfile(_ profile: InputProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "InputProfile_\(profile.id)")
        }
    }

    func getConnectedGamepadName() -> String? {
        connectedControllers.first?.extendedGamepad != nil ? "Extended Gamepad" :
        connectedControllers.first?.microGamepad != nil ? "Micro Gamepad" : nil
    }
}
