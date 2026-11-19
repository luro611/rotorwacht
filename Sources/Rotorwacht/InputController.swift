import AppKit
import RotorwachtCore

/// Keyboard state from a local event monitor, so it works regardless of which view has focus.
final class InputController {
    static let shared = InputController()

    private(set) var left = false, right = false, up = false, down = false, space = false
    /// When true, arrow keys and space are swallowed (no system beep) and Esc is forwarded.
    var capturing = false
    var onEscape: (() -> Void)?
    private var monitors: [Any] = []

    var pilot: PilotInput {
        if let s = DebugShots.script { return s(DebugShots.elapsed) }
        return PilotInput(left: left, right: right, up: up, down: down)
    }

    func start() {
        guard monitors.isEmpty else { return }
        let handler: (NSEvent) -> NSEvent? = { [weak self] e in self?.handle(e) ?? e }
        if let m = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp], handler: handler) { monitors.append(m) }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.releaseAll()
        }
    }

    func releaseAll() { left = false; right = false; up = false; down = false; space = false }

    private func handle(_ e: NSEvent) -> NSEvent? {
        let isDown = e.type == .keyDown
        // Don't interfere with shortcuts such as Cmd+Q.
        if e.modifierFlags.contains(.command) { return e }
        switch e.keyCode {
        case 123: left = isDown
        case 124: right = isDown
        case 125: down = isDown
        case 126: up = isDown
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
