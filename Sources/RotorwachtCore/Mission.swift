import Foundation

/// A point of the ground profile (world units, y up).
public struct TerrainPoint: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }

    // Compact JSON form: [x, y]
    public init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        x = try c.decode(Double.self)
        y = try c.decode(Double.self)
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(x)
        try c.encode(y)
    }
}

public struct WorldSpec: Codable, Equatable, Sendable {
    public var width: Double
    public var ceiling: Double
}

public struct BaseSpec: Codable, Equatable, Sendable {
    /// Centre of the landing pad.
    public var x: Double
    public var width: Double
}

public struct RescuePointSpec: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// "roof", "tower" or "island" (decides how it is drawn).
    public var kind: String
    public var x: Double
    public var width: Double
    /// Height of the landing surface.
    public var top: Double
    public var people: Int
    /// nil = land on it; "winch" = hover above and hoist people (no landing needed).
    public var access: String? = nil
    /// Length of the winch cable (world units).
    public var cable: Double? = nil
    /// Swaying deck: the landing surface rises and falls around `top`.
    public var heave: HeaveSpec? = nil
    public var isWinch: Bool { access == "winch" }
    public var cableLength: Double { cable ?? 130 }
}

public struct FuelSpec: Codable, Equatable, Sendable {
    public var capacity: Double
    public var burnPerSecond: Double
    public var refuelPerSecond: Double
}

public struct FloodSpec: Codable, Equatable, Sendable {
    public var startLevel: Double
    public var risePerSecond: Double
    public var maxLevel: Double
    /// Sea swell on top of the level (optional).
    public var swell: SwellSpec? = nil
}

public struct GustSpec: Codable, Equatable, Sendable {
    public var start: Double
    public var duration: Double
    /// Acceleration in world units/s², positive = towards the right.
    public var strength: Double
}

public struct WindSpec: Codable, Equatable, Sendable {
    public var base: Double
    public var gusts: [GustSpec]
}

/// The water tank of the helicopter. Optional in mission files; these defaults apply otherwise.
public struct TankSpec: Codable, Equatable, Sendable {
    public var capacity: Double
    /// Units per second while skimming over water (or standing in the camp).
    public var fillPerSecond: Double
    /// Droplets (one unit each) released per second while the drop key is held.
    public var dropPerSecond: Double
    public static let standard = TankSpec(capacity: 100, fillPerSecond: 32, dropPerSecond: 16)
}

/// A still lake: open water at a fixed level between two x positions (the ground lies below the level there).
public struct LakeSpec: Codable, Equatable, Sendable {
    public var name: String
    public var x0: Double
    public var x1: Double
    public var level: Double
}

/// Part of the landscape that can burn. `fuel` 1 = normal forest, less burns shorter.
public struct FuelZone: Codable, Equatable, Sendable {
    public var x0: Double
    public var x1: Double
    public var fuel: Double
}

public struct IgnitionSpec: Codable, Equatable, Sendable {
    public var time: Double
    public var x: Double
    public var intensity: Double
}

/// Everything that shapes how a fire behaves in a mission.
public struct FireSpec: Codable, Equatable, Sendable {
    public var cellWidth: Double
    /// Seconds a cell burns at full intensity until its fuel is gone.
    public var burnTime: Double
    /// Heat per second a full-intensity neighbour passes on (1 = ignites).
    public var spreadRate: Double
    public var zones: [FuelZone]
    public var ignitions: [IgnitionSpec]
}

/// A mission as read from its data file. All values that shape an Einsatz live here, not in code.
public struct Mission: Codable, Equatable, Sendable {
    public var id: String
    public var title: String
    public var briefing: String
    public var world: WorldSpec
    public var terrain: [TerrainPoint]
    public var base: BaseSpec
    public var rescuePoints: [RescuePointSpec]
    public var helicopters: Int
    public var capacity: Int
    public var timeLimit: Double
    public var fuel: FuelSpec
    public var flood: FloodSpec
    public var wind: WindSpec
    /// 1-based position in the campaign, shown in menus. Optional.
    public var number: Int? = nil
    /// "flood" (default) or "fire": decides wording and what hurts the people waiting.
    public var hazard: String? = nil
    /// One or two sentences for the mission card in the start menu.
    public var summary: String? = nil
    /// Short label above the title, e.g. "Einführung".
    public var tagline: String? = nil
    public var tank: TankSpec? = nil
    public var lakes: [LakeSpec]? = nil
    public var fire: FireSpec? = nil
    public var atmosphere: AtmosphereSpec? = nil
    public var storms: [StormCell]? = nil
    public var volleys: [Volley]? = nil
    public var flows: [Flow]? = nil
    public var outposts: [Outpost]? = nil
    /// Underpasses and tunnels that must be flown through.
    public var passages: [Passage]? = nil
    /// Power lines, cranes, cable cars and wind turbines.
    public var obstacles: [Obstacle]? = nil
    /// Weather changes over time (gusts, wind shifts, fog banks, thunderstorm).
    public var weather: [WeatherEvent]? = nil
    public var icing: IcingSpec? = nil
    public var heatwave: HeatSpec? = nil
    /// Practice mode (set by `practiced`): unlimited helicopters, restart at `startX`.
    public var practice: Bool? = nil
    public var startX: Double? = nil
    /// Landscape style for the picture: "valley" (default), "coast", "town", "volcano", "alpine".
    public var look: String? = nil

    public var stormList: [StormCell] { (storms ?? []) + weatherStorms }
    public var volleyList: [Volley] { volleys ?? [] }
    public var flowList: [Flow] { flows ?? [] }
    public var outpostList: [Outpost] { outposts ?? [] }
    public var isNight: Bool { atmosphere?.night ?? false }

    public var isFire: Bool { hazard == "fire" }
    public var tankSpec: TankSpec { tank ?? .standard }
    public var lakeList: [LakeSpec] { lakes ?? [] }

    public var totalPeople: Int { rescuePoints.reduce(0) { $0 + $1.people } }

    // MARK: Ground

    /// Bare terrain height (smooth interpolation between the profile points).
    public func groundHeight(at x: Double) -> Double {
        guard let first = terrain.first, let last = terrain.last else { return 0 }
        if x <= first.x { return first.y }
        if x >= last.x { return last.y }
        // Binary search for the segment.
        var lo = 0, hi = terrain.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if terrain[mid].x <= x { lo = mid } else { hi = mid }
        }
        let a = terrain[lo], b = terrain[hi]
        let t = (x - a.x) / (b.x - a.x)
        let s = t * t * (3 - 2 * t) // smoothstep
        return a.y + (b.y - a.y) * s
    }

    /// Height of whatever one can land on at x: terrain or a rooftop platform.
    public func surfaceHeight(at x: Double) -> Double {
        var h = groundHeight(at: x)
        for p in rescuePoints where abs(x - p.x) <= p.width / 2 {
            h = max(h, p.top)
        }
        return h
    }

    /// Highest surface under a horizontal span (the footprint of the helicopter).
    public func maxSurface(from x0: Double, to x1: Double) -> Double {
        var h = surfaceHeight(at: x0)
        let steps = max(1, Int(((x1 - x0) / 8).rounded(.up)))
        for i in 1...steps {
            let x = x0 + (x1 - x0) * Double(i) / Double(steps)
            h = max(h, surfaceHeight(at: x))
        }
        return h
    }

    public var baseSurface: Double { groundHeight(at: base.x) }

    // MARK: Weather and water

    public func floodLevel(at time: Double) -> Double {
        var level = min(flood.maxLevel, flood.startLevel + flood.risePerSecond * time)
        if let s = flood.swell, s.period > 0 {
            let w = 2 * Double.pi * time / s.period
            level += s.amplitude * (sin(w) * 0.75 + 0.25 * sin(w * 2.7 + 1))
        }
        return level
    }

    /// Highest the sea can get (level plus full swell), for placing rescue points above it.
    public var highestWater: Double { flood.maxLevel + (flood.swell?.amplitude ?? 0) }

    /// Ash in the air at a time, 0...1 (takes away sight).
    public func ashDensity(at time: Double) -> Double {
        guard let a = atmosphere?.ash else { return 0 }
        var v = a.base
        for g in a.pulses where time >= g.start && time <= g.start + g.duration {
            v += g.strength * sin(Double.pi * (time - g.start) / g.duration)
        }
        return min(1, max(0, v))
    }

    /// Open water level under a span: the flood or a lake, whichever stands higher there.
    public func waterLevel(from x0: Double, to x1: Double, flood: Double) -> Double {
        var level = flood
        for l in lakeList where x1 >= l.x0 && x0 <= l.x1 { level = max(level, l.level) }
        return level
    }

    /// Horizontal wind acceleration at a time. Deterministic, so tests and replays are repeatable.
    public func windAcceleration(at time: Double) -> Double {
        var w = wind.base
        for g in wind.gusts where time >= g.start && time <= g.start + g.duration {
            let phase = (time - g.start) / g.duration
            w += g.strength * sin(Double.pi * phase)
        }
        w += weatherWind(at: time)
        // Light turbulence on top.
        w += 10 * sin(time * 0.9) + 6 * sin(time * 2.3 + 1)
        return w
    }
}

extension Mission {
    public struct ValidationError: Error, CustomStringConvertible, Equatable {
        public var message: String
        public var description: String { message }
    }

    /// Checks values that would otherwise produce NaN or division by zero later. Throws the first problem found.
    public func validate() throws {
        func fail(_ m: String) throws -> Never { throw ValidationError(message: "Einsatz \(id): \(m)") }
        if world.width <= 0 || world.ceiling <= 0 { try fail("Weltgröße muss größer als 0 sein") }
        if terrain.count < 2 { try fail("Gelände braucht mindestens zwei Punkte") }
        for (a, b) in zip(terrain, terrain.dropFirst()) where b.x <= a.x {
            try fail("Geländepunkte müssen streng von links nach rechts steigen (x=\(b.x) nach x=\(a.x))")
        }
        if capacity <= 0 { try fail("capacity muss größer als 0 sein") }
        if helicopters <= 0 { try fail("helicopters muss größer als 0 sein") }
        if timeLimit <= 0 { try fail("timeLimit muss größer als 0 sein") }
        if base.width <= 0 || base.x < 0 || base.x > world.width { try fail("Lager liegt außerhalb der Welt oder hat keine Breite") }
        if fuel.capacity <= 0 || fuel.burnPerSecond < 0 || fuel.refuelPerSecond <= 0 { try fail("Treibstoffwerte unzulässig") }
        for g in wind.gusts where g.duration <= 0 { try fail("Böe bei \(g.start) s hat keine Dauer") }
        for p in rescuePoints where p.width <= 0 || p.people < 0 || p.x < 0 || p.x > world.width {
            try fail("Rettungspunkt \(p.id) hat unzulässige Werte")
        }
        for l in lakeList where l.x1 <= l.x0 { try fail("See \(l.name): x1 muss größer als x0 sein") }
        if let t = tank, t.capacity <= 0 || t.fillPerSecond <= 0 || t.dropPerSecond <= 0 { try fail("Tankwerte unzulässig") }
        if let f = fire, f.cellWidth <= 0 || f.burnTime <= 0 { try fail("Feuerwerte unzulässig") }
        for s in stormList where s.x1 <= s.x0 || s.interval <= 0 || s.warn < 0 || s.radius <= 0 { try fail("Gewitterzelle unzulässig") }
        for v in volleyList where v.count <= 0 || v.repeats <= 0 || v.x1 < v.x0 || v.stagger < 0 || v.radius <= 0
            || !["debris", "lavaBomb", "rock"].contains(v.kind) { try fail("Salve \(v.kind) unzulässig") }
        for f in flowList where f.speed <= 0 || f.warn < 0 || (f.length ?? 1) <= 0 || !["lava", "avalanche", "surge"].contains(f.kind) {
            try fail("Strom \(f.id) unzulässig")
        }
        for o in outpostList where o.width <= 0 { try fail("Außenposten \(o.name) unzulässig") }
        try validatePassages(fail)
        try validateObstacles(fail)
        try validateWeather(fail)
        try validateClimate(fail)
        if let s = flood.swell, s.period <= 0 { try fail("Wellenperiode muss größer als 0 sein") }
        for p in rescuePoints where p.isWinch && p.cableLength <= 0 { try fail("Seil von \(p.id) unzulässig") }
    }
}

public enum MissionLibrary {
    /// Missions offered in the start menu, in order.
    public static let all = ["hochwasser", "waldbrand", "kueste", "altstadt", "vulkan", "gebirge", "bohrinsel", "staudamm", "pass"]

    public enum LoadError: Error { case notFound(String) }

    /// Loads `Missions/<id>.json`: from the app bundle, from the Swift package resources, or – for
    /// plain `swiftc` builds and tests – from the source tree next to this file.
    public static func load(_ id: String) throws -> Mission {
        var candidates: [URL?] = [Bundle.main.url(forResource: id, withExtension: "json", subdirectory: "Missions")]
        #if SWIFT_PACKAGE
        candidates.append(Bundle.module.url(forResource: id, withExtension: "json", subdirectory: "Missions"))
        #endif
        candidates.append(URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Missions/\(id).json"))
        for case let url? in candidates where FileManager.default.fileExists(atPath: url.path) {
            let mission = try JSONDecoder().decode(Mission.self, from: Data(contentsOf: url))
            try mission.validate()
            return mission
        }
        throw LoadError.notFound(id)
    }
}
