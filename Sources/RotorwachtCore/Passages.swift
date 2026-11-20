import Foundation

// Passages: an underpass (bridge) or a tunnel that has to be flown through, with optional roll-up shutters.
// Above the roof the span is solid up to the flight ceiling, so a passage cannot be flown over.
// Rules and numbers: docs/planung/05 Mehr Spannung.md ("Detailentwurf").

/// A roll-up door in a tunnel that opens and closes in a fixed rhythm.
public struct Shutter: Codable, Equatable, Sendable {
    public var x: Double
    /// Seconds per cycle.
    public var period: Double
    /// Seconds per cycle in which the door is fully open.
    public var open: Double
    /// Shift of the cycle in seconds.
    public var phase: Double
    /// Seconds of warning (flashing amber light and a clack) before the door starts to close.
    public var warn: Double
    /// Height of the opening above the floor when open. Nil: up to the roof.
    public var gap: Double? = nil
    /// Seconds the door needs to close or to open. Nil: 0.6.
    public var move: Double? = nil

    public static let defaultMove = 0.6
    /// Half the thickness of the door, for hits.
    public static let halfThickness = 8.0
    public var moveTime: Double { move ?? Self.defaultMove }
}

public enum ShutterLight: Equatable, Sendable { case green, amber, red }

public struct Passage: Codable, Equatable, Sendable {
    public var id: String
    /// "bridge" or "tunnel".
    public var kind: String
    public var x0: Double
    public var x1: Double
    /// Height of the underside of the roof (world units).
    public var roof: Double
    public var shutters: [Shutter]? = nil

    /// Helicopter height from the skids to the rotor head, used for every hit with a passage.
    public static let heliHeight = 70.0
    /// Half width of the helicopter body for hits.
    public static let bodyHalfWidth = 36.0
    /// Room above the helicopter that every opening must keep (checked in `validate`).
    public static let minRoom = 36.0
    /// A door counts as open for the pilot if its lower edge is this far above the helicopter.
    public static let doorMargin = 18.0

    public var shutterList: [Shutter] { shutters ?? [] }
    public var isTunnel: Bool { kind == "tunnel" }
    public func contains(_ x: Double) -> Bool { x >= x0 && x <= x1 }

    /// Floor of the corridor: highest ground in the span or the highest water of the Einsatz.
    public func floorRef(in mission: Mission) -> Double {
        max(mission.maxSurface(from: x0, to: x1), mission.highestWater)
    }

    /// Floor at a moment: ground or the rising water, whichever is higher in the span.
    public func floor(in mission: Mission, flood: Double) -> Double {
        max(mission.maxSurface(from: x0, to: x1), flood)
    }

    // MARK: Shutter rhythm (pure functions of time)

    /// Position in the cycle, 0..<period.
    public static func cycleTime(_ s: Shutter, at t: Double) -> Double {
        let u = (t + s.phase).truncatingRemainder(dividingBy: s.period)
        return u < 0 ? u + s.period : u
    }

    /// 1 = fully open, 0 = closed.
    public static func openness(_ s: Shutter, at t: Double) -> Double {
        let u = cycleTime(s, at: t), m = s.moveTime
        if u < s.open { return 1 }
        if u < s.open + m { return 1 - (u - s.open) / m }
        if u < s.period - m { return 0 }
        return (u - (s.period - m)) / m
    }

    public static func light(_ s: Shutter, at t: Double) -> ShutterLight {
        let u = cycleTime(s, at: t)
        if u >= s.open { return .red }
        if s.warn > 0, u >= s.open - s.warn { return .amber }
        return .green
    }

    /// Height of the lower edge of the door above the floor.
    public func doorBottom(_ s: Shutter, at t: Double, floor: Double) -> Double {
        let gap = min(s.gap ?? (roof - floor), roof - floor)
        return floor + gap * Self.openness(s, at: t)
    }

    /// Whether a helicopter flying at `heliY` (skids) is hit by the door.
    public func hits(_ s: Shutter, heliX: Double, heliY: Double, at t: Double, floor: Double) -> Bool {
        abs(heliX - s.x) < Self.bodyHalfWidth + Shutter.halfThickness
            && doorBottom(s, at: t, floor: floor) < heliY + Self.heliHeight
            && heliY < roof
    }

    // MARK: Planning

    /// Whether a crossing started now (from `x` towards `direction`, +1 or -1) passes every door ahead while it is open.
    /// `speed` is the planned ground speed, `lead` the time to get going.
    public func canCross(in mission: Mission, flood: Double, from x: Double, direction: Double, at time: Double,
                         speed: Double = 190, lead: Double = 0.4, before: Double = 1.0, after: Double = 1.0) -> Bool {
        let floor = self.floor(in: mission, flood: flood)
        for s in shutterList {
            let ahead = (s.x - x) * direction
            guard ahead > -Self.bodyHalfWidth else { continue }
            let arrive = time + lead + max(0, ahead) / speed
            var t = arrive - before
            while t <= arrive + after {
                // Needs room for the helicopter flying in the middle of the corridor, not only touching the floor.
                if doorBottom(s, at: t, floor: floor) < floor + Self.heliHeight + Self.doorMargin { return false }
                t += 0.1
            }
        }
        return true
    }

    /// Height (skids) the pilot flies through the corridor: in the middle between floor and roof.
    public func corridorY(floor: Double, upTo limit: Double? = nil) -> Double {
        let top = min(roof, limit ?? roof)
        return floor + max(14, (top - floor - Self.heliHeight) / 2)
    }
}

extension Mission {
    public var passageList: [Passage] { passages ?? [] }
    /// Index of the passage whose span contains `x`.
    public func passageIndex(at x: Double) -> Int? { passageList.firstIndex { $0.contains(x) } }
}

extension Mission {
    func validatePassages(_ fail: (String) throws -> Never) throws {
        for p in passageList {
            if p.x1 <= p.x0 || p.x0 < 0 || p.x1 > world.width { try fail("Durchfahrt \(p.id): Spanne unzulässig") }
            if !["bridge", "tunnel"].contains(p.kind) { try fail("Durchfahrt \(p.id): Art unbekannt") }
            if p.roof > world.ceiling { try fail("Durchfahrt \(p.id): Decke über der Flughöhengrenze") }
            let floor = p.floorRef(in: self)
            if p.roof - floor < Passage.heliHeight + Passage.minRoom { try fail("Durchfahrt \(p.id): Öffnung zu niedrig") }
            if !p.isTunnel, !p.shutterList.isEmpty { try fail("Durchfahrt \(p.id): nur Tunnel haben Shutter") }
            for r in rescuePoints where r.x + r.width / 2 > p.x0 - 30 && r.x - r.width / 2 < p.x1 + 30 {
                try fail("Durchfahrt \(p.id): Rettungspunkt \(r.id) liegt zu nah")
            }
            for s in p.shutterList {
                if s.x < p.x0 || s.x > p.x1 { try fail("Shutter bei \(s.x) liegt außerhalb von \(p.id)") }
                if s.open <= 0 || s.warn < 0 || s.moveTime <= 0 || s.period <= s.open + 2 * s.moveTime + 0.5 {
                    try fail("Shutter bei \(s.x) in \(p.id): Takt unzulässig")
                }
                if (s.gap ?? p.roof - floor) < Passage.heliHeight + Passage.doorMargin + 4 { try fail("Shutter bei \(s.x): Öffnung zu niedrig") }
            }
            // The corridor must be level, else the roof and the doors would not match the ground.
            let lo = (stride(from: p.x0, through: p.x1, by: 10).map { groundHeight(at: $0) }.min()) ?? 0
            if p.isTunnel, floor - lo > 1 { try fail("Durchfahrt \(p.id): Gelände in der Spanne nicht eben") }
        }
    }
}

// MARK: - Simulation

extension MissionSimulation {
    /// Seconds before a closed door ahead that the helicopter should not be in its way (for hints).
    public func shutterOpenness(passage pi: Int, shutter si: Int) -> Double {
        Passage.openness(mission.passageList[pi].shutterList[si], at: time)
    }

    public func shutterLight(passage pi: Int, shutter si: Int) -> ShutterLight {
        Passage.light(mission.passageList[pi].shutterList[si], at: time)
    }

    /// Floor of a passage right now (the flood may stand in it).
    public func passageFloor(_ pi: Int) -> Double { mission.passageList[pi].floor(in: mission, flood: floodLevel) }

    /// Passage the helicopter is in (middle between the two ends), if any.
    public var passageUnderHelicopter: Int? { mission.passageIndex(at: heli.x) }

    /// Events of the door rhythm (warning clack, closing). Runs every step, also while a replacement is on its way.
    mutating func stepPassageRhythm(dt: Double, _ events: inout [SimEvent]) {
        let list = mission.passageList
        guard !list.isEmpty else { return }
        hz.passageContactCooldown = max(0, hz.passageContactCooldown - dt)
        for (pi, p) in list.enumerated() {
            for (si, s) in p.shutterList.enumerated() {
                let k = shutterKey(pi, si)
                let warnCycle = Int((((time + s.phase) - (s.open - s.warn)) / s.period).rounded(.down))
                if s.warn > 0, warnCycle > (hz.shutterWarnCycle[k] ?? warnCycle) {
                    events.append(.shutterWarning(passage: pi, shutter: si))
                }
                hz.shutterWarnCycle[k] = warnCycle
                let closeCycle = Int((((time + s.phase) - s.open) / s.period).rounded(.down))
                if closeCycle > (hz.shutterCloseCycle[k] ?? closeCycle) {
                    events.append(.shutterClosing(passage: pi, shutter: si))
                }
                hz.shutterCloseCycle[k] = closeCycle
            }
        }
    }

    /// Hits of the flying helicopter with doors, roof and end walls, after it has moved.
    mutating func stepPassages(dt: Double, _ events: inout [SimEvent]) {
        let list = mission.passageList
        guard !list.isEmpty else { return }
        let h = Passage.heliHeight, hw = Passage.bodyHalfWidth
        for (pi, p) in list.enumerated() {
            let floor = passageFloor(pi)
            for s in p.shutterList where p.hits(s, heliX: heli.x, heliY: heli.y, at: time, floor: floor) {
                heli.durability = 0
                events.append(.shutterCrush(passage: pi))
                return
            }
            guard heli.y + h > p.roof else { continue }
            if p.contains(heli.x) {
                // Ceiling: pushed down.
                let rise = max(0, heli.vy)
                heli.y = p.roof - h
                if heli.vy > 0 { heli.vy = 0 }
                var damage = 40 * dt
                if hz.passageContactCooldown <= 0 { damage += 8 + 0.15 * rise; hz.passageContactCooldown = 0.5 }
                heli.durability = max(0, heli.durability - damage)
                events.append(.passageContact(kind: "roof", damage: damage))
            } else if heli.x > p.x0 - hw, heli.x < p.x0 {
                heli.x = p.x0 - hw
                wallHit(speed: max(0, heli.vx), &events)
                heli.vx = min(heli.vx, 0)
            } else if heli.x < p.x1 + hw, heli.x > p.x1 {
                heli.x = p.x1 + hw
                wallHit(speed: max(0, -heli.vx), &events)
                heli.vx = max(heli.vx, 0)
            }
        }
    }

    private mutating func wallHit(speed: Double, _ events: inout [SimEvent]) {
        guard speed > 0, hz.passageContactCooldown <= 0 else { return }
        hz.passageContactCooldown = 0.5
        let damage = 0.12 * speed
        heli.durability = max(0, heli.durability - damage)
        events.append(.passageContact(kind: "wall", damage: damage))
    }

    private func shutterKey(_ pi: Int, _ si: Int) -> Int { pi * 100 + si }
}
