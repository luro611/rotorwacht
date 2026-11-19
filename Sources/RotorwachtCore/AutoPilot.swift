import Foundation

/// A simple scripted pilot. Used by tests to prove a mission can be won, and by the screenshot helper.
/// Not part of normal play.
public struct AutoPilot {
    /// Fight fires before rescuing anybody (used for demonstration screenshots).
    public var fireFirst = false
    public init(fireFirst: Bool = false) { self.fireFirst = fireFirst }

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

    // MARK: Fire fighting

    /// Rescue points with waiting people and the distance to the nearest flame (only those within reach).
    private func threatened(_ sim: MissionSimulation) -> [(index: Int, distance: Double, cell: Int)] {
        guard sim.mission.fire != nil else { return [] }
        var out: [(Int, Double, Int)] = []
        for (pi, p) in sim.mission.rescuePoints.enumerated()
        where sim.people.contains(where: { $0.pointIndex == pi && $0.state == .waiting }) {
            var best: (Double, Int)?
            for (ci, c) in sim.fire.cells.enumerated() where c.burning {
                let d = abs(sim.fire.center(of: ci) - p.x)
                if best == nil || d < best!.0 { best = (d, ci) }
            }
            if let b = best, b.0 < (fireFirst ? 900 : 460) { out.append((pi, b.0, b.1)) }
        }
        return out.sorted { $0.1 < $1.1 }
    }

    private func cruise(_ sim: MissionSimulation, x targetX: Double, hoverY: Double, maxSpeed: Double = 230) -> PilotInput {
        let h = sim.heli, m = sim.mission
        let dx = targetX - h.x
        var input = PilotInput()
        var desiredVx = max(-maxSpeed, min(maxSpeed, dx * 0.9))
        if abs(dx) < 250 { desiredVx = max(-110, min(110, dx * 0.7)) }
        if h.vx < desiredVx - 12 { input.right = true } else if h.vx > desiredVx + 12 { input.left = true }
        let lo = min(h.x, targetX) - 80, hi = max(h.x, targetX) + 80
        let clear = abs(dx) > 250 ? m.maxSurface(from: lo, to: hi) + 90 : m.maxSurface(from: h.x - 70, to: h.x + 70) + 45
        let wantY = max(clear, hoverY)
        let desiredVy = max(-110, min(110, (wantY - h.y) * 1.4))
        if desiredVy > h.vy + 8 { input.up = true } else if desiredVy < h.vy - 8 { input.down = true }
        return input
    }

    /// Fire mission: fly to the flames closest to people and drop water, or refill at a lake.
    private func fightInput(_ sim: MissionSimulation) -> PilotInput? {
        let m = sim.mission
        let h = sim.heli
        let threats = threatened(sim)
        guard let worst = threats.first else { return nil }
        // Someone is about to be hurt: collect them if there is room, instead of fighting on.
        if !fireFirst {
            if sim.fireExposure[worst.index] > 4.5, sim.aboardCount < m.capacity { return nil }
            if sim.aboardCount >= m.capacity - 1 { return nil }
        }
        if h.water < 18 || (sim.filling && h.water < 90) {
            guard let lake = m.lakeList.min(by: { abs(($0.x0 + $0.x1) / 2 - h.x) < abs(($1.x0 + $1.x1) / 2 - h.x) }) else { return nil }
            let cx = (lake.x0 + lake.x1) / 2
            return cruise(sim, x: cx, hoverY: lake.level + 28, maxSpeed: 200)
        }
        let tx = sim.fire.center(of: worst.cell)
        var input = cruise(sim, x: tx, hoverY: m.groundHeight(at: tx) + 85)
        // Sweep: drop while above the burning stretch near the people.
        let over = sim.fire.maxIntensity(from: h.x - 70, to: h.x + 70) > 0.1
        input.drop = over && h.y - m.surfaceHeight(at: h.x) < 230
        return input
    }

    public func input(for sim: MissionSimulation) -> PilotInput {
        let m = sim.mission
        let h = sim.heli
        guard case .flying = sim.phase else { return PilotInput() }
        if !h.onGround, let f = fightInput(sim) { return f }
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
