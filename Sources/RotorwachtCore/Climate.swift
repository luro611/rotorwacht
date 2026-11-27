import Foundation

// Building blocks of 0.9.0: swaying platforms, icing and heat. All fields are optional in mission files.
// Design: docs/planung/08 Neue Einsätze 0.9.md ("Detailentwurf").

/// A landing surface that rises and falls (deck of a ship, a raft): amplitude in world units, period in seconds,
/// `phase` as a share of the period.
public struct HeaveSpec: Codable, Equatable, Sendable {
    public var amplitude: Double
    public var period: Double
    public var phase: Double? = nil

    public func offset(at t: Double) -> Double { amplitude * sin(2 * Double.pi * (t / period + (phase ?? 0))) }
}

/// Ice builds up while flying and melts on the ground at the camp or an outpost.
public struct IcingSpec: Codable, Equatable, Sendable {
    /// Share of a full coat per second of flight.
    public var rate: Double
    /// Share melted per second on the ground at the camp or an outpost.
    public var thaw: Double
    /// Seconds before the ice starts to build up.
    public var start: Double

    /// How much thrust and climb a full coat takes away.
    public static let thrustLoss = 0.45
    public static let climbLoss = 0.35
}

/// Heat of the day: more fuel burnt, less climb. `pulses` add to `base` like the ash clouds.
public struct HeatSpec: Codable, Equatable, Sendable {
    public var base: Double
    public var pulses: [GustSpec]
    public static let climbLoss = 0.25
}

extension Mission {
    public var heaves: Bool { rescuePoints.contains { $0.heave != nil } }

    /// The mission with every swaying landing surface at its height at time `t`.
    public func swayed(at t: Double) -> Mission {
        guard heaves else { return self }
        var m = self
        for i in m.rescuePoints.indices {
            if let h = m.rescuePoints[i].heave { m.rescuePoints[i].top += h.offset(at: t) }
        }
        return m
    }

    /// Strength of the heat at a time, 0...1.
    public func swelter(at t: Double) -> Double {
        guard let h = heatwave else { return 0 }
        var v = h.base
        for g in h.pulses where t >= g.start && t <= g.start + g.duration {
            v += g.strength * sin(Double.pi * (t - g.start) / g.duration)
        }
        return min(1, max(0, v))
    }

    func validateClimate(_ fail: (String) throws -> Never) throws {
        if let i = icing, i.rate < 0 || i.thaw <= 0 || i.start < 0 { try fail("Vereisung unzulässig") }
        if let h = heatwave {
            if h.base < 0 || h.base > 1 { try fail("Hitze unzulässig") }
            for g in h.pulses where g.duration <= 0 || g.strength < 0 { try fail("Hitzewelle bei \(g.start) s unzulässig") }
        }
        for p in rescuePoints {
            guard let h = p.heave else { continue }
            if h.amplitude <= 0 || h.period <= 0 || p.isWinch { try fail("Schwanken von \(p.id) unzulässig") }
            if p.top - h.amplitude <= highestWater + 8 { try fail("\(p.id) taucht ins Wasser ein") }
            if groundHeight(at: p.x) > p.top - h.amplitude { try fail("\(p.id): Gelände ragt in die schwankende Fläche") }
        }
    }
}

extension MissionSimulation {
    /// Fuel burnt per second, with the heat of the day.
    public var fuelBurn: Double { mission.fuel.burnPerSecond * (1 + swelter) }

    /// The helicopter as it flies now: iced up and in the heat it answers more slowly.
    var flownSpec: HelicopterSpec {
        var s = spec
        s.horizontalAcceleration *= 1 - IcingSpec.thrustLoss * ice
        s.climbSpeed *= (1 - IcingSpec.climbLoss * ice) * (1 - HeatSpec.climbLoss * swelter)
        return s
    }

    mutating func stepClimate(dt: Double, _ events: inout [SimEvent]) {
        swelter = mission.swelter(at: time)
        guard let i = mission.icing else { return }
        if heli.onGround {
            if !heli.inWater, inBaseZone || outpostUnderHelicopter() != nil {
                if ice > 0.02, ice - i.thaw * dt <= 0.02 { events.append(.deiced) }
                ice = max(0, ice - i.thaw * dt)
            }
        } else if time >= i.start {
            let before = ice
            ice = min(1, ice + i.rate * dt)
            if before < 0.5, ice >= 0.5 { events.append(.iced) }
        }
    }
}
