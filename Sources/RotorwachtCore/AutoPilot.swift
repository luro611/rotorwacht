import Foundation

/// A simple scripted pilot. Used by tests to prove a mission can be won, and by the screenshot helper.
/// Not part of normal play.
public struct AutoPilot {
    /// Fight fires before rescuing anybody (used for demonstration screenshots).
    public var fireFirst = false
    public init(fireFirst: Bool = false) { self.fireFirst = fireFirst }

    /// Seconds until a ground flow (lava, avalanche) reaches a rescue point, nil if none is on its way.
    private func flowEta(_ sim: MissionSimulation, point p: RescuePointSpec) -> Double? {
        var best: Double?
        for f in sim.mission.flowList {
            let lo = min(f.x0, f.x1), hi = max(f.x0, f.x1)
            guard p.x >= lo - 1, p.x <= hi + 1 else { continue }
            // The front arrives at the near edge of the point, seen from where the flow starts.
            let edge = f.x1 >= f.x0 ? p.x - p.width / 2 : p.x + p.width / 2
            let eta = f.start + abs(edge - f.x0) / f.speed - sim.time
            if best == nil || eta < best! { best = eta }
        }
        return best
    }

    /// Nearest place to refuel (camp or outpost) and its pad height.
    private func refuelPlace(_ sim: MissionSimulation, from x: Double) -> (x: Double, top: Double, outpost: Bool) {
        let m = sim.mission
        var best = (x: m.base.x, top: m.baseSurface, outpost: false)
        for o in m.outpostList where abs(o.x - x) < abs(best.x - x) {
            best = (o.x, m.groundHeight(at: o.x), true)
        }
        return best
    }

    private func pickTarget(_ sim: MissionSimulation) -> (x: Double, top: Double, pointIndex: Int?) {
        let m = sim.mission
        let heli = sim.heli
        // People hoisted by the cable are not counted until they are aboard (else the pilot would give up mid-hoist).
        let settled = sim.people.filter { $0.state == .aboard || $0.state == .boarding }.count
        let full = settled >= m.capacity
        // Points with waiting people that are not yet lost.
        let open = m.rescuePoints.enumerated().filter { i, _ in
            sim.people.contains { $0.pointIndex == i && ($0.state == .waiting || $0.state == .hoisting) }
        }
        let usable = open.filter { !sim.isBlocked($0.offset) }
        if full || open.isEmpty {
            return refuelOr(sim, (m.base.x, m.baseSurface, nil))
        }
        // Blocked points are visited only when nothing else is left.
        let pool = usable.isEmpty ? open : usable
        // The point that is in most danger first: by the time a flow arrives, else flood height and distance.
        let best = pool.min { a, b in
            func score(_ e: (offset: Int, element: RescuePointSpec)) -> Double {
                let travel = abs(e.element.x - heli.x) / 200
                if let eta = flowEta(sim, point: e.element) {
                    // Reachable points by urgency; unreachable ones last.
                    return eta > travel ? eta : 10_000 + eta
                }
                return abs(e.element.x - heli.x) * 0.002 + e.element.top * 0.01 + (m.flowList.isEmpty ? 0 : 5_000)
            }
            return score(a) < score(b)
        }!
        // Nearly full and the next stop has more people than there is room for: fly home first.
        let room = m.capacity - settled
        let waitingThere = sim.people.filter { $0.pointIndex == best.offset && $0.state == .waiting }.count
        if settled > 0, room <= 1, waitingThere > room, best.offset != sim.hz.winch?.pointIndex {
            return refuelOr(sim, (m.base.x, m.baseSurface, nil))
        }
        return refuelOr(sim, (best.element.x, best.element.top, best.offset))
    }

    /// With outposts on the map the fuel is scarce: refuel first when it would not last to the target and back.
    private func refuelOr(_ sim: MissionSimulation, _ t: (x: Double, top: Double, pointIndex: Int?)) -> (x: Double, top: Double, pointIndex: Int?) {
        let m = sim.mission
        guard !m.outpostList.isEmpty, sim.heli.fuel < m.fuel.capacity * 0.9 else { return t }
        let burn = m.fuel.burnPerSecond * 1.4
        let toTarget = abs(t.x - sim.heli.x) / 190 * burn
        let back = refuelPlace(sim, from: t.x)
        let backCost = abs(back.x - t.x) / 190 * burn + 10
        if sim.heli.fuel - toTarget > backCost { return t }
        let r = refuelPlace(sim, from: sim.heli.x)
        return (r.x, r.top, nil)
    }

    /// Hover above a winch point and hold still while the cable works.
    private func winchInput(_ sim: MissionSimulation, point p: RescuePointSpec) -> PilotInput {
        let h = sim.heli, m = sim.mission
        let dx = p.x - h.x
        var input = PilotInput()
        let near = abs(dx) < 140
        if near {
            // Critically damped hover with the wind worked out: thrust = wanted acceleration - what wind and drag do anyway.
            let wanted = 1.44 * dx - 2.4 * h.vx
            let thrust = wanted - (sim.wind - 0.5 * h.vx)
            if thrust > 35 { input.right = true } else if thrust < -35 { input.left = true }
        } else {
            let desiredVx = max(-230, min(230, dx * 0.9))
            if h.vx < desiredVx - 12 { input.right = true } else if h.vx > desiredVx + 12 { input.left = true }
        }
        let floor = m.maxSurface(from: h.x - 60, to: h.x + 60) + 40
        let wantY: Double
        if abs(dx) > 160 {
            let lo = min(h.x, p.x) - 80, hi = max(h.x, p.x) + 80
            wantY = max(m.maxSurface(from: lo, to: hi) + 90, p.top + 90)
        } else {
            wantY = max(floor, p.top + p.cableLength * 0.5)
        }
        let desiredVy = max(-100, min(100, (wantY - h.y) * 1.4))
        if desiredVy > h.vy + 6 { input.up = true } else if desiredVy < h.vy - 6 { input.down = true }
        return input
    }

    /// Step aside from an announced lightning strike.
    private func dodge(_ sim: MissionSimulation) -> PilotInput? {
        for s in sim.hz.strikes where s.age == nil {
            guard let cell = sim.mission.stormList.first(where: { s.x >= $0.x0 - 1 && s.x <= $0.x1 + 1 }) else { continue }
            let d = sim.heli.x - s.x
            if abs(d) < cell.radius + 60 {
                var input = PilotInput()
                if d >= 0 { input.right = true } else { input.left = true }
                let want = sim.mission.maxSurface(from: sim.heli.x - 70, to: sim.heli.x + 70) + 60
                if sim.heli.y < want { input.up = true }
                return input
            }
        }
        return nil
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

    // MARK: Passages

    /// Where the pilot waits in front of a passage and how far in front of it the crossing counts as started.
    private static let stageDistance = 170.0
    private static let commitDistance = 130.0
    private static let crossSpeed = 190.0
    private static let tailDistance = Passage.bodyHalfWidth + 30

    private func steer(_ sim: MissionSimulation, vx desiredVx: Double, y wantY: Double) -> PilotInput {
        let h = sim.heli
        var input = PilotInput()
        if h.vx < desiredVx - 12 { input.right = true } else if h.vx > desiredVx + 12 { input.left = true }
        let desiredVy = max(-110, min(110, (wantY - h.y) * 1.4))
        if desiredVy > h.vy + 8 { input.up = true } else if desiredVy < h.vy - 8 { input.down = true }
        return input
    }

    /// Flies through an underpass or tunnel on the way to `target`: waits in front of closing doors until a window fits.
    private func passageInput(_ sim: MissionSimulation, target: (x: Double, top: Double, pointIndex: Int?)) -> PilotInput? {
        let m = sim.mission, h = sim.heli
        let dir: Double = target.x > h.x ? 1 : -1
        for (pi, p) in m.passageList.enumerated() {
            let entry = dir > 0 ? p.x0 : p.x1, exit = dir > 0 ? p.x1 : p.x0
            let before = (entry - h.x) * dir
            let past = (h.x - exit) * dir
            guard (target.x - exit) * dir > 0, before < 500 else { continue }
            if past >= Self.tailDistance {
                // Just out of the passage: climb slowly until the terrain ahead is cleared, then the normal flight takes over.
                guard past < Self.tailDistance + 320 else { continue }
                let lo = min(h.x, h.x + dir * 420) - 70, hi = max(h.x, h.x + dir * 420) + 70
                let need = max(m.maxSurface(from: lo, to: hi) + 70, target.top + 70)
                if h.y < need - 15 { return steer(sim, vx: dir * 70, y: need) }
                continue
            }
            let floor = sim.passageFloor(pi)
            let limit = p.shutterList.compactMap(\.gap).min().map { floor + $0 } ?? p.roof
            let y = p.corridorY(floor: floor, upTo: limit)
            let inBand = h.y >= floor + 10 && h.y + Passage.heliHeight <= min(p.roof, limit) - 6
            if before <= Self.commitDistance {
                return steer(sim, vx: dir * Self.crossSpeed, y: y)
            }
            let stage = entry - dir * Self.stageDistance
            let launching = before <= Self.stageDistance + 40
            if launching, inBand,
               p.canCross(in: m, flood: sim.floodLevel, from: h.x, direction: dir, at: sim.time) {
                return steer(sim, vx: dir * Self.crossSpeed, y: y)
            }
            // Wait at the staging point, descending to the corridor height once the ground allows it.
            let lo = min(h.x, stage) - 70, hi = max(h.x, stage) + 70
            let wantY = max(y, m.maxSurface(from: lo, to: hi) + 30)
            let vx = max(-110, min(110, (stage - h.x) * 0.7))
            return steer(sim, vx: vx, y: wantY)
        }
        return nil
    }

    public func input(for sim: MissionSimulation) -> PilotInput {
        let m = sim.mission
        let h = sim.heli
        guard case .flying = sim.phase else { return PilotInput() }
        if let d = dodge(sim) { return d }
        if !h.onGround, let f = fightInput(sim) { return f }
        let target = pickTarget(sim)
        if !h.onGround, !m.passageList.isEmpty, let p = passageInput(sim, target: target) { return p }
        if let pi = target.pointIndex, m.rescuePoints[pi].isWinch, !(h.onGround && !h.inWater && sim.people.contains { $0.state == .boarding || $0.state == .leaving }) {
            if h.onGround { return PilotInput(up: true) }
            return winchInput(sim, point: m.rescuePoints[pi])
        }

        // Landed: stay while people walk, otherwise lift off when work is done here.
        if h.onGround && !h.inWater {
            let busy = sim.people.contains { $0.state == .boarding || $0.state == .leaving }
            if busy { return PilotInput() }
            if sim.outpostUnderHelicopter() != nil, h.fuel < m.fuel.capacity * 0.97 { return PilotInput() }
            if sim.inBaseZone {
                let aboard = sim.aboardCount > 0
                let needFuel = h.fuel < m.fuel.capacity * 0.97
                if aboard || needFuel { return PilotInput() }
            }
            if let pi = sim.rescuePointUnderHelicopter() {
                let waiting = sim.people.contains { $0.pointIndex == pi && $0.state == .waiting }
                if waiting && sim.aboardCount < m.capacity && !sim.isBlocked(pi) { return PilotInput() }
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
            let corridor = m.maxSurface(from: min(h.x, target.x) - 70, to: max(h.x, target.x) + 70) + 60
            let wantY = abs(dx) < 300 ? max(target.top + 70, surfaceHere + 40, corridor) : cruise
            desiredVy = max(-110, min(110, (wantY - h.y) * 1.4))
        }
        if desiredVy > h.vy + 8 { input.up = true }
        else if desiredVy < h.vy - 8 { input.down = true }
        return input
    }
}
