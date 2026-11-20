import Foundation

// Weather changes during an Einsatz: gusts, wind shifts, fog banks and an approaching thunderstorm.
// Everything is a function of the mission time, so tests and replays repeat exactly. A warning comes first.
// Design: docs/planung/06 Abwechslung 0.7.md.

public struct WeatherEvent: Codable, Equatable, Sendable {
    /// "gust", "windShift", "fog" or "thunder".
    public var kind: String
    public var start: Double
    public var duration: Double
    /// Seconds of warning before `start` (windsock, line on the screen).
    public var warn: Double
    /// gust, windShift: acceleration in world units/s², positive = towards the right.
    public var strength: Double? = nil
    /// fog: how much of the view is lost, 0...0.9.
    public var density: Double? = nil
    /// fog, thunder: stretch of the map. Nil: everywhere.
    public var x0: Double? = nil
    public var x1: Double? = nil
    /// fog: "fog" (grey-white, default) or "dust" (brown).
    public var tint: String? = nil
    /// thunder: seconds between strikes, radius and damage of a strike, warning before each strike.
    public var interval: Double? = nil
    public var radius: Double? = nil
    public var damage: Double? = nil
    public var strikeWarn: Double? = nil

    /// Seconds a wind shift needs to build up and to die down, and a fog bank to roll in and out.
    public var ramp: Double { max(0.5, min(kind == "fog" ? 6 : 4, duration / 3)) }
    public var end: Double { start + duration }

    /// 0...1 over time: ramps up from `start` (wind shift, fog), stays, ramps down before `end`; zero outside.
    func envelope(at t: Double) -> Double {
        guard t >= start, t <= end else { return 0 }
        let r = ramp
        let up = min(1, (t - start) / r), down = min(1, (end - t) / r)
        let v = min(up, down)
        return v * v * (3 - 2 * v)
    }
}

/// What the pilot is told about weather that is on its way.
public struct WeatherNotice: Equatable, Sendable {
    public var kind: String
    public var secondsLeft: Double
    /// +1 wind towards the right, -1 towards the left, 0 for fog and thunder.
    public var direction: Int
    public var index: Int
}

extension Mission {
    public var weatherList: [WeatherEvent] { weather ?? [] }

    /// Wind acceleration added by the weather schedule at a time.
    public func weatherWind(at t: Double) -> Double {
        var w = 0.0
        for e in weatherList {
            let s = e.strength ?? 0
            switch e.kind {
            case "gust":
                if t >= e.start, t <= e.end { w += s * sin(Double.pi * (t - e.start) / e.duration) }
            case "windShift":
                w += s * e.envelope(at: t)
            default: break
            }
        }
        return w
    }

    /// Fog at a place and time: share of the view lost (0...0.9) and the colour. Fades out near the ends of a bank.
    public func fog(at t: Double, x: Double) -> (density: Double, tint: String) {
        var best = (density: 0.0, tint: "fog")
        for e in weatherList where e.kind == "fog" {
            var d = (e.density ?? 0.6) * e.envelope(at: t)
            if let a = e.x0, let b = e.x1 {
                let outside = x < a ? a - x : (x > b ? x - b : 0)
                d *= max(0, 1 - outside / 200)
            }
            if d > best.density { best = (d, e.tint ?? "fog") }
        }
        best.density = min(0.9, best.density)
        return best
    }

    /// Thunderstorm building up over the mission, 0...1: the sky darkens from `start - warn` and clears after the end.
    public func thunderBuildup(at t: Double) -> Double {
        var v = 0.0
        for e in weatherList where e.kind == "thunder" {
            let from = e.start - max(e.warn, 4)
            if t < from || t > e.end + 8 { continue }
            let up = min(1, (t - from) / max(e.warn, 4)), down = min(1, (e.end + 8 - t) / 8)
            v = max(v, min(up, down))
        }
        return v
    }

    /// Lightning cells of thunderstorms in the schedule, handled like `storms`.
    var weatherStorms: [StormCell] {
        weatherList.filter { $0.kind == "thunder" }.map {
            StormCell(x0: $0.x0 ?? 0, x1: $0.x1 ?? world.width, start: $0.start, interval: $0.interval ?? 9,
                      warn: $0.strikeWarn ?? 2.6, radius: $0.radius ?? 170, damage: $0.damage ?? 18, until: $0.end)
        }
    }

    /// Weather that has been announced but not yet begun at time `t`.
    public func weatherNotices(at t: Double) -> [WeatherNotice] {
        var out: [WeatherNotice] = []
        for (i, e) in weatherList.enumerated() where e.warn > 0 && t >= e.start - e.warn && t < e.start {
            let s = e.strength ?? 0
            out.append(WeatherNotice(kind: e.kind, secondsLeft: e.start - t, direction: s > 0 ? 1 : (s < 0 ? -1 : 0), index: i))
        }
        return out
    }
}

extension Mission {
    func validateWeather(_ fail: (String) throws -> Never) throws {
        for e in weatherList {
            if !["gust", "windShift", "fog", "thunder"].contains(e.kind) { try fail("Wetter \(e.kind) unbekannt") }
            if e.duration <= 0 || e.start < 0 || e.warn < 0 { try fail("Wetter \(e.kind) bei \(e.start) s: Zeiten unzulässig") }
            if e.kind == "gust" || e.kind == "windShift" {
                guard let s = e.strength, abs(s) <= 260 else { try fail("Wetter \(e.kind) bei \(e.start) s: Stärke fehlt oder ist zu groß") }
            }
            if e.kind == "fog", let d = e.density, d <= 0 || d > 0.9 { try fail("Nebel bei \(e.start) s: Dichte unzulässig") }
            if let a = e.x0, let b = e.x1, b <= a { try fail("Wetter \(e.kind) bei \(e.start) s: x1 muss größer als x0 sein") }
            if e.kind == "thunder", (e.interval ?? 1) <= 0 || (e.radius ?? 1) <= 0 || (e.damage ?? 0) < 0 || (e.strikeWarn ?? 0) < 0 {
                try fail("Gewitter bei \(e.start) s unzulässig")
            }
        }
    }
}

// MARK: - Simulation

extension MissionSimulation {
    /// Weather that is on its way, for the windsock and the line on the screen.
    public var weatherNotices: [WeatherNotice] { mission.weatherNotices(at: time) }
    /// Fog at the helicopter right now.
    public var fog: (density: Double, tint: String) { mission.fog(at: time, x: heli.x) }
    public var thunderBuildup: Double { mission.thunderBuildup(at: time) }

    mutating func stepWeather(_ events: inout [SimEvent]) {
        for (i, e) in mission.weatherList.enumerated() where e.warn > 0 && time >= e.start - e.warn && !hz.weatherWarned.contains(i) {
            hz.weatherWarned.insert(i)
            events.append(.weatherWarning(kind: e.kind, seconds: max(0, e.start - time)))
        }
    }
}
