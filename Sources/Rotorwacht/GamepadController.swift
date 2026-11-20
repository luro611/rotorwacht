import AppKit
import GameController
import RotorwachtCore

/// Connects GameController (Xbox, PlayStation, MFi controllers) to the pure logic in `GamepadInterpreter`.
/// Polls the first controller with an extended gamepad at 60 Hz on the main thread.
final class GamepadController: ObservableObject {
    static let shared = GamepadController()

    /// Name of the connected controller, nil when none.
    @Published private(set) var name: String?
    /// Latest flight input (neutral without controller or while the app is in the background).
    private(set) var pilot = PilotInput()
    /// Called for every update with pause, confirm, back and menu moves.
    var onOutput: ((GamepadOutput) -> Void)?
    /// Called when a controller that was connected disappears.
    var onDisconnect: (() -> Void)?

    private var interpreter = GamepadInterpreter()
    private var timer: Timer?
    private var lastTime = CACurrentMediaTime()
    private var current: GCController?
    private let deadzoneKey = "gamepadDeadzone"

    /// Stick deadzone, stored in the user defaults.
    var deadzone: Double {
        get { interpreter.tuning.deadzone }
        set {
            interpreter.tuning.deadzone = min(max(newValue, 0.05), 0.4)
            UserDefaults.standard.set(interpreter.tuning.deadzone, forKey: deadzoneKey)
            objectWillChange.send()
        }
    }

    func start() {
        guard timer == nil else { return }
        if UserDefaults.standard.object(forKey: deadzoneKey) != nil {
            interpreter.tuning.deadzone = min(max(UserDefaults.standard.double(forKey: deadzoneKey), 0.05), 0.4)
        }
        let nc = NotificationCenter.default
        nc.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        nc.addObserver(forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        nc.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.interpreter.reset(); self?.pilot = PilotInput()
        }
        refresh()
        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func refresh() {
        let pad = GCController.controllers().first { $0.extendedGamepad != nil }
        let hadPad = current != nil
        current = pad
        let newName = pad.map { $0.vendorName ?? "Controller" }
        if newName != name { name = newName }
        if pad == nil {
            interpreter.reset()
            pilot = PilotInput()
            if hadPad { onDisconnect?() }
        }
    }

    private func poll() {
        let now = CACurrentMediaTime()
        let dt = min(0.1, now - lastTime)
        lastTime = now
        guard let pad = current?.extendedGamepad, NSApp.isActive else { return }
        let sample = GamepadSample(
            stickX: Double(pad.leftThumbstick.xAxis.value), stickY: Double(pad.leftThumbstick.yAxis.value),
            dpadX: Double(pad.dpad.xAxis.value), dpadY: Double(pad.dpad.yAxis.value),
            a: pad.buttonA.isPressed, b: pad.buttonB.isPressed, start: pad.buttonMenu.isPressed)
        let out = interpreter.update(sample, dt: dt)
        pilot = out.pilot
        onOutput?(out)
    }
}
