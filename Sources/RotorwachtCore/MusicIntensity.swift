import Foundation

/// What the music needs to know about the mission, a few times per second. The app fills it from the on-screen display.
public struct MusicInputs: Equatable, Sendable {
    /// 1 - time left / time limit, 0...1.
    public var timeUsed = 0.0
    /// Tank fraction 0...1.
    public var fuel = 1.0
    public var durability = 1.0
    /// Flood progress 0...1 (0 for missions without rising water).
    public var flood = 0.0
    /// Burning stretches, 0...1 (burning cell count relative to a large fire).
    public var fire = 0.0
    /// Smoke and heat at the helicopter, 0...1.
    public var smoke = 0.0
    public var heat = 0.0
    public var lost = 0
    public var helicoptersLeft = 3
    public var crashed = false

    public init() {}
}

/// Turns the mission state into the music intensity (0.12 calm ... 1 desperate).
/// Time pressure, low fuel, rising water or fire, damage and fresh misfortunes raise it quickly; it falls back slowly.
public struct IntensityTracker: Sendable {
    public static let calm = 0.12
    public private(set) var value = IntensityTracker.calm
    /// A short surge from events (lost person, hit, lost helicopter), decays over a few seconds.
    public private(set) var alarm = 0.0
    private var previous: MusicInputs?

    public init() {}

    private static func smooth(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        let t = min(1, max(0, (x - lo) / (hi - lo)))
        return t * t * (3 - 2 * t)
    }

    /// Where the intensity wants to go for these inputs.
    public static func target(_ i: MusicInputs, alarm: Double = 0) -> Double {
        let parts: [Double] = [
            smooth(i.timeUsed, 0.55, 1.0) * 0.8,
            smooth(1 - i.fuel, 0.65, 0.97) * 0.7,
            min(1, max(0, i.flood)) * 0.55,
            min(1, max(0, i.fire)) * 0.6,
            max(i.smoke, i.heat) * 0.5,
            (1 - min(1, max(0, i.durability))) * 0.6,
            min(1, alarm) * 0.7,
            i.crashed ? 0.9 : 0
        ]
        // Probabilistic OR: any single strong cause is enough, several add up, never above 1.
        let calm = calm
        let pressure = 1 - parts.reduce(1) { $0 * (1 - min(1, max(0, $1))) }
        return min(1, calm + (1 - calm) * pressure)
    }

    public mutating func reset() { self = IntensityTracker() }

    /// Moves the intensity `dt` seconds on and returns it.
    @discardableResult
    public mutating func update(_ i: MusicInputs, dt: Double) -> Double {
        if let p = previous {
            if i.lost > p.lost { alarm = min(1, alarm + 0.6) }
            if i.helicoptersLeft < p.helicoptersLeft { alarm = min(1, alarm + 0.8) }
            let hit = p.durability - i.durability
            if hit > 0.01 { alarm = min(1, alarm + min(0.8, hit * 3)) }
        }
        previous = i
        alarm = max(0, alarm - dt / 6)
        let t = IntensityTracker.target(i, alarm: alarm)
        // Up within about two seconds, down within about eight.
        let tau = t > value ? 1.5 : 7.0
        value += (t - value) * (1 - exp(-dt / tau))
        return value
    }
}

/// Sound settings of the player.
public struct SoundSettings: Equatable, Codable, Sendable {
    public var musicOn = true
    /// 0...1
    public var musicVolume = 0.6
    /// 0...1; 0 = effects off.
    public var effectsVolume = 1.0

    public init() {}

    public var clamped: SoundSettings {
        var s = self
        s.musicVolume = min(1, max(0, musicVolume))
        s.effectsVolume = min(1, max(0, effectsVolume))
        return s
    }
}
