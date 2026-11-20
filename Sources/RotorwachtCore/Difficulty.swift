import Foundation

/// Three levels per Einsatz. They scale numbers of the mission data; the data files stay "medium".
public enum Difficulty: String, Codable, CaseIterable, Sendable {
    case easy, medium, hard

    public var label: String {
        switch self { case .easy: "Leicht"; case .medium: "Mittel"; case .hard: "Schwer" }
    }

    /// Time allowed.
    var time: Double { switch self { case .easy: 1.3; case .medium: 1; case .hard: 0.85 } }
    /// Fuel burn, wind, flood and fire speed, hazard damage and flow speed.
    var pressure: Double { switch self { case .easy: 0.8; case .medium: 1; case .hard: 1.2 } }
    /// Warning times (longer when easy).
    var warning: Double { switch self { case .easy: 1.3; case .medium: 1; case .hard: 0.8 } }
    /// Height of the openings of passages.
    var opening: Double { switch self { case .easy: 1.15; case .medium: 1; case .hard: 0.9 } }
    var helicopters: Int { switch self { case .easy: 4; case .medium: 3; case .hard: 2 } }
}

extension Mission {
    /// The mission as played on a level. Medium returns the data unchanged.
    public func scaled(for level: Difficulty) -> Mission {
        guard level != .medium else { return self }
        var m = self
        let p = level.pressure
        m.timeLimit *= level.time
        m.helicopters = level.helicopters
        m.fuel.burnPerSecond *= p
        m.wind.base *= p
        m.wind.gusts = m.wind.gusts.map { var g = $0; g.strength *= p; return g }
        m.flood.risePerSecond *= p
        if var f = m.fire { f.spreadRate *= p; m.fire = f }
        m.storms = m.storms?.map { var s = $0; s.damage *= p; s.warn *= level.warning; return s }
        m.volleys = m.volleys?.map { var v = $0; v.damage *= p; v.warn *= level.warning; return v }
        m.flows = m.flows?.map { var f = $0; f.speed *= p; f.damagePerSecond *= p; f.warn *= level.warning; return f }
        m.passages = m.passages?.map { scaledPassage($0, level) }
        m.obstacles = m.obstacles?.map { var o = $0; o.damage = ($0.damage ?? Obstacle.defaultWireDamage) * p; return o }
        m.weather = m.weather?.map { e in
            var w = e
            w.warn *= level.warning
            w.strength = e.strength.map { $0 * p }
            w.density = e.density.map { min(0.9, $0 * p) }
            w.damage = e.damage.map { $0 * p }
            w.strikeWarn = e.strikeWarn.map { $0 * level.warning }
            return w
        }
        return m
    }
}

extension Mission {
    /// Passages on a level: rhythm of the doors, warning time and height of the openings.
    fileprivate func scaledPassage(_ p: Passage, _ level: Difficulty) -> Passage {
        var q = p
        let floor = p.floorRef(in: self)
        let room = Passage.heliHeight + Passage.minRoom
        let open = p.roof - floor
        let newOpen = max(room, open * level.opening)
        q.roof = floor + newOpen
        q.shutters = p.shutters?.map { s in
            var t = s
            let closed = s.period - s.open
            t.open = s.open * level.warning
            t.period = t.open + closed * (2 - level.warning)
            t.warn = s.warn * level.warning
            if let g = s.gap { t.gap = max(Passage.heliHeight + Passage.doorMargin + 4, min(g * level.opening, newOpen)) }
            return t
        }
        return q
    }
}
