import Foundation

/// Raw values of a controller at one moment (no GameController types, so it is testable without a device).
public struct GamepadSample: Equatable, Sendable {
    /// Left stick and D-pad, -1...1; y positive = up.
    public var stickX = 0.0, stickY = 0.0
    public var dpadX = 0.0, dpadY = 0.0
    /// A / Cross.
    public var a = false
    /// B / Circle.
    public var b = false
    /// Start / Menu / Options.
    public var start = false
    public init(stickX: Double = 0, stickY: Double = 0, dpadX: Double = 0, dpadY: Double = 0,
                a: Bool = false, b: Bool = false, start: Bool = false) {
        self.stickX = stickX; self.stickY = stickY; self.dpadX = dpadX; self.dpadY = dpadY
        self.a = a; self.b = b; self.start = start
    }
}

public enum MenuMove: Equatable, Sendable { case up, down, left, right }

public struct GamepadTuning: Equatable, Sendable {
    /// Stick values below this count as zero (stick drift).
    public var deadzone = 0.18
    /// Exponent of the response curve after the deadzone (1 = linear, larger = finer near the middle).
    public var curve = 1.5
    /// Digital (key-like) flags and menu moves switch on above `on` and off below `off`.
    public var on = 0.5, off = 0.35
    /// Menu auto-repeat while a direction is held.
    public var repeatDelay = 0.4, repeatInterval = 0.12
    public init() {}
}

/// What one controller update produced.
public struct GamepadOutput: Equatable, Sendable {
    public var pilot = PilotInput()
    /// Rising edges (true for exactly one update).
    public var pause = false, confirm = false, back = false
    /// Menu moves, with auto-repeat.
    public var moves: [MenuMove] = []
    public init() {}
}

/// Turns controller samples into flight input, pause and menu events. Pure logic, no UI.
public struct GamepadInterpreter: Sendable {
    public var tuning: GamepadTuning
    private var held: [MenuMove: Double] = [:]      // time since the direction began (for repeat)
    private var lastRepeat: [MenuMove: Double] = [:]
    private var digital: [MenuMove: Bool] = [:]
    private var prev = GamepadSample()

    public init(tuning: GamepadTuning = GamepadTuning()) { self.tuning = tuning }

    /// Deadzone, rescale to 0...1 and curve; keeps the sign.
    public static func shape(_ v: Double, tuning t: GamepadTuning) -> Double {
        let a = min(1, abs(v))
        guard a > t.deadzone else { return 0 }
        let r = (a - t.deadzone) / (1 - t.deadzone)
        return (v < 0 ? -1 : 1) * pow(r, t.curve)
    }

    /// D-pad wins when pressed, otherwise the shaped stick.
    private func axis(stick: Double, dpad: Double) -> Double {
        abs(dpad) > 0.5 ? (dpad < 0 ? -1 : 1) : Self.shape(stick, tuning: tuning)
    }

    /// Forget everything (controller removed or app in the background).
    public mutating func reset() {
        held = [:]; lastRepeat = [:]; digital = [:]; prev = GamepadSample()
    }

    public mutating func update(_ s: GamepadSample, dt: Double) -> GamepadOutput {
        var out = GamepadOutput()
        let x = axis(stick: s.stickX, dpad: s.dpadX)
        let y = axis(stick: s.stickY, dpad: s.dpadY)

        // Flight: analog values; the flags follow with hysteresis so liftoff, fuel use and the winch work as with keys.
        var p = PilotInput()
        p.axisX = x; p.axisY = y
        func flag(_ m: MenuMove, _ v: Double) -> Bool {
            let was = digital[m] ?? false
            let now = was ? abs(v) > tuning.off : abs(v) > tuning.on
            digital[m] = now
            return now
        }
        p.right = x > 0 && flag(.right, x)
        p.left = x < 0 && flag(.left, x)
        p.up = y > 0 && flag(.up, y)
        p.down = y < 0 && flag(.down, y)
        if x == 0 { digital[.left] = false; digital[.right] = false }
        if y == 0 { digital[.up] = false; digital[.down] = false }
        p.drop = s.a
        out.pilot = p

        // Menu: same flags, plus repeat.
        let dirs: [(MenuMove, Bool)] = [(.left, p.left), (.right, p.right), (.up, p.up), (.down, p.down)]
        for (m, on) in dirs {
            if on {
                let t = (held[m] ?? -dt) + dt
                if held[m] == nil { out.moves.append(m); lastRepeat[m] = 0 }
                else if t >= tuning.repeatDelay, t - (lastRepeat[m] ?? 0) >= tuning.repeatInterval || lastRepeat[m] == 0 {
                    out.moves.append(m); lastRepeat[m] = t
                }
                held[m] = t
            } else {
                held[m] = nil; lastRepeat[m] = nil
            }
        }

        out.pause = s.start && !prev.start
        out.confirm = s.a && !prev.a
        out.back = s.b && !prev.b
        prev = s
        return out
    }
}

/// Focus on a grid whose rows can have different lengths (start menu: Stufen, then Einsätze).
public struct GridFocus: Equatable, Sendable {
    public private(set) var rowLengths: [Int]
    public private(set) var row = 0, col = 0
    public init(rowLengths: [Int], row: Int = 0, col: Int = 0) {
        self.rowLengths = rowLengths.filter { $0 > 0 }
        self.row = min(max(0, row), max(0, self.rowLengths.count - 1))
        self.col = 0
        self.col = min(max(0, col), max(0, (self.rowLengths.isEmpty ? 1 : self.rowLengths[self.row]) - 1))
    }

    public mutating func move(_ m: MenuMove) {
        guard !rowLengths.isEmpty else { return }
        switch m {
        case .left: col = max(0, col - 1)
        case .right: col = min(rowLengths[row] - 1, col + 1)
        case .up: row = max(0, row - 1)
        case .down: row = min(rowLengths.count - 1, row + 1)
        }
        col = min(col, rowLengths[row] - 1)
    }
}
