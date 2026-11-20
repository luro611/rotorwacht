import AppKit
import RotorwachtCore

/// Keyboard state from a local event monitor, so it works regardless of which view has focus.
final class InputController {
    static let shared = InputController()

    private var keyLeft = false, keyRight = false, keyUp = false, keyDown = false, space = false
    /// Thrust demand for the engine sound, from keys or the controller.
    var up: Bool { keyUp || GamepadController.shared.pilot.up }
    var down: Bool { keyDown || GamepadController.shared.pilot.down }
    /// When true, arrow keys and space are swallowed (no system beep) and Esc is forwarded.
    var capturing = false
    var onEscape: (() -> Void)?
    private var monitors: [Any] = []

    var pilot: PilotInput {
        if let s = DebugShots.script { return s(DebugShots.elapsed) }
        let keys = PilotInput(left: keyLeft, right: keyRight, up: keyUp, down: keyDown, drop: space)
        var pad = GamepadController.shared.pilot
        // Keys win as soon as one is held; the fire button works from either device.
        if keyLeft || keyRight || keyUp || keyDown { var k = keys; k.drop = space || pad.drop; return k }
        pad.drop = pad.drop || space
        return pad
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> NSEvent? = { [weak self] e in self?.handle(e) ?? e }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: handler) { monitors.append(m) }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.releaseAll()
        }
    }

    func releaseAll() { keyLeft = false; keyRight = false; keyUp = false; keyDown = false; space = false }

    private func handle(_ e: NSEvent) -> NSEvent? {
        let isDown = e.type == .keyDown
        // Don't interfere with shortcuts such as Cmd+Q.
        if e.modifierFlags.contains(.command) { return e }
        switch e.keyCode {
        case 123: keyLeft = isDown
        case 124: keyRight = isDown
        case 125: keyDown = isDown
        case 126: keyUp = isDown
        case 49: space = isDown
        case 53:
            if capturing {
                if isDown && !e.isARepeat { onEscape?() }
                return nil
            }
            return e
        default: return e
        }
        return capturing ? nil : e
    }
}
