import Foundation

// Obstacles: power lines, cranes with a swinging jib, cable cars with a moving gondola, wind turbines.
// Every obstacle stands on the ground and can always be flown over. Positions of the moving parts are pure
// functions of time, so hits and pictures use the same numbers. Design: docs/planung/06 Abwechslung 0.7.md.

/// A thick line (capsule) or a circle (both ends equal) that hurts the helicopter.
public struct ObstacleShape: Equatable, Sendable {
    public var x0: Double
    public var y0: Double
    public var x1: Double
    public var y1: Double
    public var radius: Double
    /// Solid parts (blades, jib, gondola, towers) destroy the helicopter; wires and ropes only hurt.
    public var solid: Bool
}

public struct Obstacle: Codable, Equatable, Sendable {
    public var id: String
    /// "powerline", "crane", "cablecar" or "windmill".
    public var kind: String
    /// First mast, or the tower of a crane or a wind turbine.
    public var x: Double
    /// Second mast (power line, cable car).
    public var x1: Double? = nil
    /// Height above the ground: attachment of the wires, top of the tower, hub of the wind turbine.
    public var height: Double
    /// Same at the second mast. Nil: like `height`.
    public var height1: Double? = nil
    /// Sag of wires as a share of the span.
    public var sag: Double? = nil
    /// Crane: length of the jib. Wind turbine: length of a blade.
    public var reach: Double? = nil
    /// Crane: length of the rope. Default 90.
    public var rope: Double? = nil
    /// Seconds per swing (crane), per round trip (cable car) or per turn (wind turbine).
    public var period: Double? = nil
    /// Start of the cycle as a share of the period.
    public var phase: Double? = nil
    /// Damage of a wire or rope hit. Nil: 40.
    public var damage: Double? = nil

    public static let defaultWireDamage = 40.0
    /// Seconds between two damaging contacts.
    public static let contactCooldown = 0.7
    /// Margin the autopilot keeps above the envelope, and the free distance to pads, camp and passages.
    public static let clearMargin = 80.0
    public static let padDistance = 70.0
    /// Room that must stay between the top of an obstacle and the flight ceiling.
    public static let ceilingRoom = 150.0
    public static let counterJib = 0.35

    public var isLine: Bool { kind == "powerline" || kind == "cablecar" }
    public var wireDamage: Double { damage ?? Self.defaultWireDamage }
    var cyclePeriod: Double { max(0.5, period ?? (kind == "windmill" ? 6 : (kind == "cablecar" ? 40 : 14))) }
    var cycleStart: Double { phase ?? 0 }
    var jib: Double { reach ?? (kind == "windmill" ? 90 : 160) }
    var ropeLength: Double { rope ?? 90 }

    // MARK: Time functions

    /// Crane: share of the jib length seen from the side (-1...1), the jib slews around the tower.
    public func swing(at t: Double) -> Double { cos(2 * Double.pi * (t / cyclePeriod + cycleStart)) }

    /// Cable car: position of the gondola on the cable (0 = first station, 1 = second), slows down at the ends.
    public func gondola(at t: Double) -> Double { 0.5 - 0.5 * cos(2 * Double.pi * (t / cyclePeriod + cycleStart)) }

    /// Wind turbine: angle of the first blade in radians.
    public func bladeAngle(at t: Double) -> Double { 2 * Double.pi * (t / cyclePeriod + cycleStart) }

    // MARK: Geometry

    /// Fixed points of the wires: (x, y) of the two masts' attachments.
    public func anchors(in mission: Mission) -> (a: (x: Double, y: Double), b: (x: Double, y: Double)) {
        let xb = x1 ?? x
        return ((x, mission.groundHeight(at: x) + height), (xb, mission.groundHeight(at: xb) + (height1 ?? height)))
    }

    /// Height of a wire between the masts at `u` (0...1) with sag.
    public func wireY(in mission: Mission, u: Double, drop: Double = 0, sagFactor: Double? = nil) -> Double {
        let (a, b) = anchors(in: mission)
        let span = abs(b.x - a.x)
        let s = (sagFactor ?? sag ?? (kind == "cablecar" ? 0.02 : 0.05)) * span
        return a.y + (b.y - a.y) * u - 4 * s * u * (1 - u) - drop
    }

    /// The two wires of a power line hang at these distances below the attachment.
    public static let wireDrops: [Double] = [0, 44]
    public static let gondolaDrop = 46.0
    public static let gondolaRadius = 26.0

    /// Position of the gondola, middle of the cabin.
    public func gondolaCenter(at t: Double, in mission: Mission) -> (x: Double, y: Double) {
        let (a, b) = anchors(in: mission)
        let u = gondola(at: t)
        return (a.x + (b.x - a.x) * u, wireY(in: mission, u: u) - Self.gondolaDrop)
    }

    /// Everything that can hurt the helicopter at time `t`.
    public func shapes(at t: Double, in mission: Mission) -> [ObstacleShape] {
        var out: [ObstacleShape] = []
        func seg(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ r: Double, solid: Bool) {
            out.append(ObstacleShape(x0: x0, y0: y0, x1: x1, y1: y1, radius: r, solid: solid))
        }
        let (a, b) = anchors(in: mission)
        switch kind {
        case "powerline", "cablecar":
            let n = 12
            let drops = kind == "powerline" ? Self.wireDrops : [0]
            for d in drops {
                var px = a.x, py = wireY(in: mission, u: 0, drop: d)
                for i in 1...n {
                    let u = Double(i) / Double(n)
                    let qx = a.x + (b.x - a.x) * u, qy = wireY(in: mission, u: u, drop: d)
                    seg(px, py, qx, qy, 5, solid: false)
                    px = qx; py = qy
                }
            }
            for (p, xx) in [(a, x), (b, x1 ?? x)] {
                let g = mission.groundHeight(at: xx)
                seg(xx, g, xx, p.y, 8, solid: true)
            }
            if kind == "cablecar" {
                let c = gondolaCenter(at: t, in: mission)
                seg(c.x, c.y + Self.gondolaDrop, c.x, c.y + 14, 3, solid: false)
                seg(c.x, c.y, c.x, c.y, Self.gondolaRadius, solid: true)
            }
        case "crane":
            let g = mission.groundHeight(at: x), top = g + height
            let f = swing(at: t), tip = x + jib * f
            seg(x, g, x, top + 46, 10, solid: true)
            seg(x, top, tip, top, 7, solid: true)
            seg(x, top, x - Self.counterJib * jib * f, top, 7, solid: true)
            seg(tip, top, tip, top - ropeLength, 3, solid: false)
            seg(tip, top - ropeLength - 16, tip, top - ropeLength - 16, 18, solid: true)
        case "windmill":
            let g = mission.groundHeight(at: x), hub = g + height
            seg(x, g, x, hub, 9, solid: true)
            for k in 0..<3 {
                let th = bladeAngle(at: t) + Double(k) * 2 * Double.pi / 3
                seg(x, hub, x + jib * cos(th), hub + jib * sin(th), 7, solid: true)
            }
        default: break
        }
        return out
    }

    /// Widest extent and top of the obstacle over all times: (x0, x1, top). The helicopter never needs to enter it.
    public func envelope(in mission: Mission) -> (x0: Double, x1: Double, top: Double) {
        let (a, b) = anchors(in: mission)
        switch kind {
        case "powerline", "cablecar":
            return (min(a.x, b.x) - 12, max(a.x, b.x) + 12, max(a.y, b.y) + 14)
        case "crane":
            let top = mission.groundHeight(at: x) + height
            return (x - jib - 24, x + jib + 24, top + 60)
        default: // windmill
            return (x - jib - 10, x + jib + 10, mission.groundHeight(at: x) + height + jib + 10)
        }
    }

    /// Whether a circle touches a part that is there at `t`; `solid` tells which kind of part it was.
    public func touch(circleX cx: Double, y cy: Double, radius cr: Double, at t: Double, in mission: Mission) -> ObstacleShape? {
        for s in shapes(at: t, in: mission) {
            if Self.distance(px: cx, py: cy, s) <= s.radius + cr { return s }
        }
        return nil
    }

    static func distance(px: Double, py: Double, _ s: ObstacleShape) -> Double {
        let dx = s.x1 - s.x0, dy = s.y1 - s.y0
        let len2 = dx * dx + dy * dy
        let u = len2 > 0 ? max(0, min(1, ((px - s.x0) * dx + (py - s.y0) * dy) / len2)) : 0
        return hypot(px - (s.x0 + dx * u), py - (s.y0 + dy * u))
    }
}

extension Mission {
    public var obstacleList: [Obstacle] { obstacles ?? [] }

    /// Top of the highest obstacle whose envelope (plus `margin`) meets the span, or nil.
    public func obstacleTop(from x0: Double, to x1: Double, margin: Double = 60) -> Double? {
        var top: Double?
        for o in obstacleList {
            let e = o.envelope(in: self)
            if e.x1 + margin >= min(x0, x1), e.x0 - margin <= max(x0, x1) { top = max(top ?? e.top, e.top) }
        }
        return top
    }
}

extension Mission {
    func validateObstacles(_ fail: (String) throws -> Never) throws {
        for o in obstacleList {
            if !["powerline", "crane", "cablecar", "windmill"].contains(o.kind) { try fail("Hindernis \(o.id): Art unbekannt") }
            if o.x < 0 || o.x > world.width || o.height <= 0 { try fail("Hindernis \(o.id): Lage oder Höhe unzulässig") }
            if o.isLine {
                guard let xb = o.x1, xb > o.x + 40, xb <= world.width else { try fail("Hindernis \(o.id): zweiter Mast fehlt oder liegt zu nah") }
                if (o.height1 ?? o.height) <= 0 { try fail("Hindernis \(o.id): Höhe am zweiten Mast unzulässig") }
            }
            if let p = o.period, p <= 0 { try fail("Hindernis \(o.id): Periode unzulässig") }
            if let s = o.sag, s < 0 || s > 0.3 { try fail("Hindernis \(o.id): Durchhang unzulässig") }
            if o.kind == "crane" || o.kind == "windmill", (o.reach ?? 1) <= 0 { try fail("Hindernis \(o.id): Länge unzulässig") }
            if (o.damage ?? 1) < 0 { try fail("Hindernis \(o.id): Schaden unzulässig") }
            let e = o.envelope(in: self)
            if e.x0 < 0 || e.x1 > world.width { try fail("Hindernis \(o.id): ragt aus der Welt") }
            if e.top > world.ceiling - Obstacle.ceilingRoom { try fail("Hindernis \(o.id): zu hoch, nicht mehr überfliegbar") }
            if o.kind == "windmill", o.height - o.jib < 20 { try fail("Hindernis \(o.id): Flügel berühren den Boden") }
            let free = Obstacle.padDistance
            for r in rescuePoints where r.x + r.width / 2 > e.x0 - free && r.x - r.width / 2 < e.x1 + free {
                try fail("Hindernis \(o.id): Rettungspunkt \(r.id) liegt zu nah")
            }
            if base.x + base.width / 2 > e.x0 - free && base.x - base.width / 2 < e.x1 + free { try fail("Hindernis \(o.id): liegt am Lager") }
            for p in outpostList where p.x + p.width / 2 > e.x0 - free && p.x - p.width / 2 < e.x1 + free {
                try fail("Hindernis \(o.id): Außenposten \(p.name) liegt zu nah")
            }
            for p in passageList where p.x1 > e.x0 - free && p.x0 < e.x1 + free { try fail("Hindernis \(o.id): liegt an Durchfahrt \(p.id)") }
        }
    }
}

// MARK: - Simulation

extension MissionSimulation {
    /// Circles that make up the helicopter for hits: skids, body, rotor.
    static let heliCircles: [(dy: Double, r: Double)] = [(14, 24), (38, 28), (62, 26)]

    /// Hits of the flying helicopter with obstacles, after it has moved.
    mutating func stepObstacles(dt: Double, _ events: inout [SimEvent]) {
        let list = mission.obstacleList
        guard !list.isEmpty else { return }
        hz.obstacleCooldown = max(0, hz.obstacleCooldown - dt)
        for o in list {
            let e = o.envelope(in: mission)
            guard heli.x > e.x0 - 60, heli.x < e.x1 + 60, heli.y < e.top + 60 else { continue }
            for c in Self.heliCircles {
                guard let s = o.touch(circleX: heli.x, y: heli.y + c.dy, radius: c.r, at: time, in: mission) else { continue }
                if s.solid {
                    heli.durability = 0
                    events.append(.obstacleHit(kind: o.kind, damage: 100, x: heli.x, y: heli.y + c.dy))
                    return
                }
                if hz.obstacleCooldown <= 0 {
                    hz.obstacleCooldown = Obstacle.contactCooldown
                    heli.durability = max(0, heli.durability - o.wireDamage)
                    events.append(.obstacleHit(kind: o.kind, damage: o.wireDamage, x: heli.x, y: heli.y + c.dy))
                }
                return
            }
        }
    }
}
