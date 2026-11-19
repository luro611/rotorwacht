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
        min(flood.maxLevel, flood.startLevel + flood.risePerSecond * time)
    }

    /// Horizontal wind acceleration at a time. Deterministic, so tests and replays are repeatable.
    public func windAcceleration(at time: Double) -> Double {
        var w = wind.base
        for g in wind.gusts where time >= g.start && time <= g.start + g.duration {
            let phase = (time - g.start) / g.duration
            w += g.strength * sin(Double.pi * phase)
        }
        // Light turbulence on top.
        w += 10 * sin(time * 0.9) + 6 * sin(time * 2.3 + 1)
        return w
    }
}

public enum MissionLibrary {
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
            return try JSONDecoder().decode(Mission.self, from: Data(contentsOf: url))
        }
        throw LoadError.notFound(id)
    }
}
