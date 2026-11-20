import Testing
@testable import RotorwachtCore

@Suite struct GamepadTests {
    let dt = 1.0 / 60

    @Test func deadzoneIgnoresDrift() {
        var g = GamepadInterpreter()
        let o = g.update(GamepadSample(stickX: 0.12, stickY: -0.15), dt: dt)
        #expect(o.pilot.horizontal == 0 && o.pilot.vertical == 0)
        #expect(!o.pilot.left && !o.pilot.right && !o.pilot.up && !o.pilot.down)
        #expect(o.moves.isEmpty)
    }

    @Test func stickIsAnalogAndMonotone() {
        var g = GamepadInterpreter()
        let small = g.update(GamepadSample(stickX: 0.4), dt: dt).pilot.horizontal
        let big = g.update(GamepadSample(stickX: 0.8), dt: dt).pilot.horizontal
        let full = g.update(GamepadSample(stickX: 1.0), dt: dt).pilot.horizontal
        #expect(small > 0 && small < big && big < full)
        #expect(abs(full - 1) < 1e-9)
        let left = g.update(GamepadSample(stickX: -1), dt: dt).pilot.horizontal
        #expect(abs(left + 1) < 1e-9)
    }

    @Test func dpadIsFullDeflection() {
        var g = GamepadInterpreter()
        let o = g.update(GamepadSample(dpadX: 1, dpadY: -1), dt: dt)
        #expect(o.pilot.horizontal == 1 && o.pilot.vertical == -1)
        #expect(o.pilot.right && o.pilot.down)
    }

    @Test func flagsHaveHysteresis() {
        var g = GamepadInterpreter()
        // Shaped value of 0.6 raw is about 0.4 after deadzone and curve, below "on".
        #expect(!g.update(GamepadSample(stickY: 0.6), dt: dt).pilot.up)
        #expect(g.update(GamepadSample(stickY: 0.9), dt: dt).pilot.up)
        // Back to a value between off and on: stays set.
        let mid = g.update(GamepadSample(stickY: 0.8), dt: dt).pilot
        #expect(mid.up == (mid.vertical > g.tuning.off))
        #expect(!g.update(GamepadSample(stickY: 0.0), dt: dt).pilot.up)
    }

    @Test func lowStickLiftsOffOnlyWhenFlagSet() {
        // Soft stick climbs slower than a full one.
        let m = makeMission()
        var soft = HelicopterState(x: 1000, y: 300, fuel: 100); soft.onGround = false
        var hard = soft
        var ps = PilotInput(); ps.axisY = 0.4
        var ph = PilotInput(); ph.axisY = 1.0; ph.up = true
        for _ in 0..<90 {
            _ = HelicopterPhysics.step(&soft, input: ps, dt: 1.0/60, wind: 0, waterLevel: -100, mission: m, fuelBurnPerSecond: 0.5)
            _ = HelicopterPhysics.step(&hard, input: ph, dt: 1.0/60, wind: 0, waterLevel: -100, mission: m, fuelBurnPerSecond: 0.5)
        }
        #expect(soft.y > 300 && soft.y < hard.y)
    }

    @Test func keyboardInputUnchanged() {
        let p = PilotInput(left: true, up: true)
        #expect(p.horizontal == -1 && p.vertical == 1)
        #expect(PilotInput(left: true, right: true).horizontal == 0)
    }

    @Test func dropFollowsAButton() {
        var g = GamepadInterpreter()
        #expect(g.update(GamepadSample(a: true), dt: dt).pilot.drop)
        #expect(!g.update(GamepadSample(a: false), dt: dt).pilot.drop)
    }

    @Test func buttonsAreEdges() {
        var g = GamepadInterpreter()
        let o1 = g.update(GamepadSample(a: true, b: true, start: true), dt: dt)
        #expect(o1.confirm && o1.back && o1.pause)
        let o2 = g.update(GamepadSample(a: true, b: true, start: true), dt: dt)
        #expect(!o2.confirm && !o2.back && !o2.pause)
        _ = g.update(GamepadSample(), dt: dt)
        #expect(g.update(GamepadSample(start: true), dt: dt).pause)
    }

    @Test func menuMovesOnceThenRepeats() {
        var g = GamepadInterpreter()
        var moves = 0
        let first = g.update(GamepadSample(dpadY: -1), dt: dt)
        #expect(first.moves == [.down])
        moves += 1
        // Held for 0.3 s: nothing new yet.
        for _ in 0..<18 { moves += g.update(GamepadSample(dpadY: -1), dt: dt).moves.count }
        #expect(moves == 1)
        // Held for 1 s in total: repeats come, about every 0.12 s after 0.4 s.
        for _ in 0..<42 { moves += g.update(GamepadSample(dpadY: -1), dt: dt).moves.count }
        #expect(moves >= 5 && moves <= 7)
        // Release and press again: moves at once.
        _ = g.update(GamepadSample(), dt: dt)
        #expect(g.update(GamepadSample(dpadY: -1), dt: dt).moves == [.down])
    }

    @Test func resetClearsHeldState() {
        var g = GamepadInterpreter()
        _ = g.update(GamepadSample(dpadX: 1, start: true), dt: dt)
        g.reset()
        let o = g.update(GamepadSample(dpadX: 1, start: true), dt: dt)
        #expect(o.moves == [.right] && o.pause)
    }

    @Test func gridFocusMovesAndClamps() {
        var f = GridFocus(rowLengths: [3, 3, 3])
        f.move(.up); f.move(.left)
        #expect(f.row == 0 && f.col == 0)
        f.move(.right); f.move(.right); f.move(.right)
        #expect(f.col == 2)
        f.move(.down); f.move(.down); f.move(.down)
        #expect(f.row == 2 && f.col == 2)
        var g = GridFocus(rowLengths: [3, 1], row: 0, col: 2)
        g.move(.down)
        #expect(g.row == 1 && g.col == 0)
        var e = GridFocus(rowLengths: [])
        e.move(.down)
        #expect(e.row == 0)
    }
}
