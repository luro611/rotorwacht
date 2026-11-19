import Foundation

/// A simple scripted pilot. Used by tests to prove a mission can be won, and by the screenshot helper.
/// Not part of normal play.
public struct AutoPilot {
    public init() {}

    private func pickTarget(_ sim: MissionSimulation) -> (x: Double, top: Double, pointIndex: Int?) {
        let m = sim.mission
        let heli = sim.heli
        let full = sim.aboardCount >= m.capacity
        // Points with waiting people that are not yet lost.
        let open = m.rescuePoints.enumerated().filter { i, _ in
            sim.people.contains { $0.pointIndex == i && $0.state == .waiting }
        }
        if full || open.isEmpty || (sim.aboardCount > 0 && sim.aboardCount >= max(1, m.capacity - 1)) {
            return (m.base.x, m.baseSurface, nil)
        }
        // The point that floods first, among those not too far (simple urgency rule).
        let best = open.min { a, b in
            let da = abs(a.element.x - heli.x) * 0.002 + a.element.top * 0.01
            let db = abs(b.element.x - heli.x) * 0.002 + b.element.top * 0.01
            return da < db
        }!
        return (best.element.x, best.element.top, best.offset)
    }

    public func input(for sim: MissionSimulation) -> PilotInput {
        let m = sim.mission
        let h = sim.heli
        guard case .flying = sim.phase else { return PilotInput() }
        let target = pickTarget(sim)

        // Landed: stay while people walk, otherwise lift off when work is done here.
        if h.onGround && !h.inWater {
            let busy = sim.people.contains { $0.state == .boarding || $0.state == .leaving }
            if busy { return PilotInput() }
            if sim.inBaseZone {
                let aboard = sim.aboardCount > 0
                let needFuel = h.fuel < m.fuel.capacity * 0.97
                if aboard || needFuel { return PilotInput() }
            }
            if let pi = sim.rescuePointUnderHelicopter() {
                let waiting = sim.people.contains { $0.pointIndex == pi && $0.state == .waiting }
                if waiting && sim.aboardCount < m.capacity { return PilotInput() }
            }
            return PilotInput(up: true)
        }

        let dx = target.x - h.x
        let landingZone = abs(dx) < 50
        // Cruise altitude: clear everything between here and the target.
        let lo = min(h.x, target.x) - 60, hi = max(h.x, target.x) + 60
        let cruise = max(m.maxSurface(from: lo, to: hi) + 100, target.top + 90)
        let surfaceHere = max(m.maxSurface(from: h.x - 45, to: h.x + 45), sim.floodLevel)

        var desiredVx = max(-260, min(260, dx * 0.9))
        if abs(dx) < 300 { desiredVx = max(-110, min(110, dx * 0.7)) }
        // Wind pushes; the proportional controller below compensates.
        var input = PilotInput()
        if h.vx < desiredVx - 12 { input.right = true }
        else if h.vx > desiredVx + 12 { input.left = true }

        var desiredVy: Double
        if landingZone && abs(h.vx) < 35 {
            let height = h.y - surfaceHere
            desiredVy = -max(18, min(70, height * 1.0))
        } else {
            let wantY = abs(dx) < 300 ? max(target.top + 70, surfaceHere + 40) : cruise
            desiredVy = max(-110, min(110, (wantY - h.y) * 1.4))
        }
        if desiredVy > h.vy + 8 { input.up = true }
        else if desiredVy < h.vy - 8 { input.down = true }
        return input
    }
}
