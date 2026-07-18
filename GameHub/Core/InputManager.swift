import Foundation
import UIKit
import GameController

class InputManager: ObservableObject {
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

    private var virtualKeyboard: UIInputView?
    private var mousePosition: CGPoint = .zero
    private var rightStickCenter: CGPoint = .zero

    init() {
        setupControllerObserver()
        loadDefaultProfile()
    }

    private func setupControllerObserver() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerConnected),
            name: .GCControllerDidConnect,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(controllerDisconnected),
            name: .GCControllerDidDisconnect,
            object: nil
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

        controller.microGamepad?.valueChangedHandler = { [weak self] gamepad, element in
            self?.handleMicroGamepadInput(gamepad: gamepad, element: element)
        }
    }

    private func handleGamepadInput(gamepad: GCExtendedGamepad, element: GCControllerElement) {
        guard let profile = activeProfile else { return }

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

        if element == gamepad.buttonA {
            handleButtonPress(button: "a", pressed: gamepad.buttonA.isPressed)
        }
        if element == gamepad.buttonB {
            handleButtonPress(button: "b", pressed: gamepad.buttonB.isPressed)
        }
        if element == gamepad.buttonX {
            handleButtonPress(button: "x", pressed: gamepad.buttonX.isPressed)
        }
        if element == gamepad.buttonY {
            handleButtonPress(button: "y", pressed: gamepad.buttonY.isPressed)
        }

        if element == gamepad.leftTrigger {
            handleTrigger(value: gamepad.leftTrigger.value, trigger: "left")
        }
        if element == gamepad.rightTrigger {
            handleTrigger(value: gamepad.rightTrigger.value, trigger: "right")
        }

        if element == gamepad.leftShoulder {
            handleButtonPress(button: "leftShoulder", pressed: gamepad.leftShoulder.isPressed)
        }
        if element == gamepad.rightShoulder {
            handleButtonPress(button: "rightShoulder", pressed: gamepad.rightShoulder.isPressed)
        }
    }

    private func handleMicroGamepadInput(gamepad: GCGamepad, element: GCControllerElement) {
        if element == gamepad.buttonA {
            handleButtonPress(button: "a", pressed: gamepad.buttonA.isPressed)
        }
        if element == gamepad.buttonX {
            handleButtonPress(button: "x", pressed: gamepad.buttonX.isPressed)
        }
    }

    private func handleLeftStick(x: Float, y: Float) {
        let deadzone: Float = 0.15
        let adjustedX = abs(x) > deadzone ? x : 0
        let adjustedY = abs(y) > deadzone ? y : 0

        sendKeyToWine(key: "w", pressed: adjustedY > 0.5)
        sendKeyToWine(key: "s", pressed: adjustedY < -0.5)
        sendKeyToWine(key: "a", pressed: adjustedX < -0.5)
        sendKeyToWine(key: "d", pressed: adjustedX > 0.5)
    }

    private func handleRightStick(x: Float, y: Float) {
        let sensitivity: Float = 10.0
        let deltaX = x * sensitivity
        let deltaY = y * sensitivity

        if abs(deltaX) > 0.5 || abs(deltaY) > 0.5 {
            moveMouseBy(dx: CGFloat(deltaX), dy: CGFloat(deltaY))
        }
    }

    private func handleButtonPress(button: String, pressed: Bool) {
        guard let profile = activeProfile else { return }

        if let mapping = profile.buttonMappings.first(where: { $0.gamepadButton == button }) {
            if pressed {
                sendKeyToWine(key: mapping.keyboardKey, pressed: true)
                if let mouseBtn = mapping.mouseButton {
                    sendMouseButtonToWine(button: mouseBtn, pressed: true)
                }
            } else {
                sendKeyToWine(key: mapping.keyboardKey, pressed: false)
                if let mouseBtn = mapping.mouseButton {
                    sendMouseButtonToWine(button: mouseBtn, pressed: false)
                }
            }
        }
    }

    private func handleTrigger(value: Float, trigger: String) {
        if value > 0.5 {
            if trigger == "left" {
                sendMouseButtonToWine(button: 1, pressed: true)
            } else {
                sendMouseButtonToWine(button: 0, pressed: true)
            }
        } else {
            if trigger == "left" {
                sendMouseButtonToWine(button: 1, pressed: false)
            } else {
                sendMouseButtonToWine(button: 0, pressed: false)
            }
        }
    }

    func sendKeyToWine(key: String, pressed: Bool) {
        let keyCode = mapKeyToKeyCode(key)
        let event = pressed ? 1 : 0

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["key", "--repeat", "\(event)", keyCode]
        try? process.run()
    }

    func sendMouseButtonToWine(button: Int, pressed: Bool) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["mousedown", "\(button)"]
        try? process.run()
    }

    func moveMouseBy(dx: CGFloat, dy: CGFloat) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["mousemove", "--relative", "\(Int(dx))", "\(Int(dy))"]
        try? process.run()
    }

    private func mapKeyToKeyCode(_ key: String) -> String {
        let keyMap: [String: String] = [
            "a": "a", "b": "b", "x": "x", "y": "y",
            "up": "Up", "down": "Down", "left": "Left", "right": "Right",
            "start": "Return", "select": "Escape",
            "leftShoulder": "Tab", "rightShoulder": "BackSpace",
            "leftStick": "space", "rightStick": "Return",
        ]
        return keyMap[key] ?? key
    }

    func handleTouchBegan(location: CGPoint, viewSize: CGSize) {
        isTouchscreenActive = true
        let scaledX = location.x / viewSize.width * 1920
        let scaledY = location.y / viewSize.height * 1080

        moveMouseTo(x: Int(scaledX), y: Int(scaledY))
    }

    func handleTouchMoved(location: CGPoint, viewSize: CGSize) {
        let scaledX = location.x / viewSize.width * 1920
        let scaledY = location.y / viewSize.height * 1080

        moveMouseTo(x: Int(scaledX), y: Int(scaledY))
    }

    func handleTouchEnded() {
        isTouchscreenActive = false
    }

    func handleTap(location: CGPoint, viewSize: CGSize) {
        sendMouseButtonToWine(button: 0, pressed: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.sendMouseButtonToWine(button: 0, pressed: false)
        }
    }

    func handleDoubleTap(location: CGPoint, viewSize: CGSize) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["click", "1", "--repeat", "2", "50"]
        try? process.run()
    }

    func handleLongPress(location: CGPoint, viewSize: CGSize) {
        sendMouseButtonToWine(button: 2, pressed: true)
    }

    func handleLongPressEnded() {
        sendMouseButtonToWine(button: 2, pressed: false)
    }

    func handlePinch(scale: CGFloat) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["key", "plus"]
        try? process.run()
    }

    func handlePan(translation: CGPoint) {
        let deltaX = translation.x * 2
        let deltaY = translation.y * 2
        moveMouseBy(dx: deltaX, dy: deltaY)
    }

    private func moveMouseTo(x: Int, y: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
        process.arguments = ["mousemove", "\(x)", "\(y)"]
        try? process.run()
    }

    func toggleKeyboard() {
        isKeyboardVisible.toggle()
    }

    func sendTextInput(_ text: String) {
        for char in text {
            sendKeyToWine(key: String(char), pressed: true)
            sendKeyToWine(key: String(char), pressed: false)
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

    func loadProfile(_ profile: InputProfile) {
        activeProfile = profile
    }

    func saveProfile(_ profile: InputProfile) {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: "InputProfile_\(profile.id)")
        }
    }

    func getConnectedGamepadName() -> String? {
        return connectedControllers.first?.extendedGamepad != nil ? "Extended Gamepad" :
               connectedControllers.first?.microGamepad != nil ? "Micro Gamepad" : nil
    }
}
