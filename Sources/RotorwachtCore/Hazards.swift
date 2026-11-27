import Foundation

// Reusable hazard building blocks. Every Einsatz combines them in its JSON file; nothing here is specific to one mission.
//
//  - `StormCell`   lightning: announced first, then strikes
//  - `Volley`      falling or flying objects: debris (aftershocks), lava bombs, rocks
//  - `Flow`        a moving band on the ground: lava stream, avalanche
//  - winch         `RescuePointSpec.access == "winch"`: hover and hold still instead of landing
//  - `Outpost`     a place where the helicopter can refuel
//  - `Atmosphere`  look of the sky (night, ash, snow) and ash that takes away sight

/// A thunderstorm over a stretch of the map. Strikes are announced `warn` seconds before they hit.
public struct StormCell: Codable, Equatable, Sendable {
    public var x0: Double
    public var x1: Double
    public var start: Double
    public var interval: Double
    public var warn: Double
    /// Helicopter within this distance (x) of the strike is hit.
    public var radius: Double
    public var damage: Double
    /// Last moment a strike may be announced. Nil: until the end (thunderstorms of the weather schedule set it).
    public var until: Double? = nil
}

/// Objects that fall or fly: `kind` is "debris" (falls straight down), "lavaBomb" or "rock" (launched, ballistic).
public struct Volley: Codable, Equatable, Sendable {
    public var kind: String
    public var start: Double
    /// Seconds between volleys (ignored when `repeats` is 1).
    public var interval: Double
    public var repeats: Int
    /// Objects per volley.
    public var count: Int
    /// Seconds between the objects of one volley.
    public var stagger: Double
    public var x0: Double
    public var x1: Double
    public var spawnY: Double
    /// Launch speed and angle (degrees, 0 = right, 90 = up). Both zero for objects that just fall.
    public var speedMin: Double
    public var speedMax: Double
    public var angleMin: Double
    public var angleMax: Double
    public var gravity: Double
    /// Rumble or sky warning before each volley, in seconds.
    public var warn: Double
    public var radius: Double
    public var damage: Double
    /// Seconds a rescue point stays unusable when an object lands on it (0 = does not block).
    public var blockTime: Double
}

/// A band that moves across the ground and hurts what it covers: lava stream ("lava"), avalanche ("avalanche") or
/// flood wave of a broken dam ("surge").
public struct Flow: Codable, Equatable, Sendable {
    public var id: String
    public var kind: String
    public var start: Double
    public var warn: Double
    public var x0: Double
    public var x1: Double
    public var speed: Double
    /// Length of the moving band. Nil: it grows and stays (lava); otherwise it passes through and leaves (avalanche).
    public var length: Double?
    /// Helicopter damage per second when it is inside the band and lower than `clearance` above the ground.
    public var damagePerSecond: Double
    public var clearance: Double
}

public struct Outpost: Codable, Equatable, Sendable {
    public var name: String
    public var x: Double
    public var width: Double
}

/// Sea swell: the water level moves up and down.
public struct SwellSpec: Codable, Equatable, Sendable {
    public var amplitude: Double
    public var period: Double
}

public struct AshSpec: Codable, Equatable, Sendable {
    /// Constant ash in the air, 0...1 of the view lost.
    public var base: Double
    /// Heavier clouds; `strength` is the extra amount (0...1) at the peak.
    public var pulses: [GustSpec]
}

public struct AtmosphereSpec: Codable, Equatable, Sendable {
    /// "dusk" (default), "night", "ash", "alpine", "dust"
    public var sky: String
    /// "rain", "snow", "ash", "dust" or nil
    public var precipitation: String?
    public var ash: AshSpec?
    public var night: Bool { sky == "night" }
}

// MARK: - Runtime state

public struct Strike: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var timeLeft: Double
    /// Seconds since the bolt came down (nil while still announced).
    public var age: Double?
}

public struct FlyingObject: Equatable, Sendable {
    public var id: Int
    public var kind: String
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
    public var gravity: Double
    public var radius: Double
    public var damage: Double
    public var blockTime: Double
}

/// Something that landed and lies on the ground for a while (debris pile, cooling lava).
public struct Rubble: Equatable, Sendable {
    public var id: Int
    public var kind: String
    public var x: Double
    public var y: Double
    public var until: Double
}

public struct FlowState: Equatable, Sendable {
    public var started = false
    public var front = 0.0
    public var tail = 0.0
    public var warned = false
    /// Current covered span.
    public var span: (lo: Double, hi: Double)? {
        guard started else { return nil }
        let lo = min(front, tail), hi = max(front, tail)
        return hi - lo > 0.5 ? (lo, hi) : nil
    }
    public static func == (a: FlowState, b: FlowState) -> Bool {
        a.started == b.started && a.front == b.front && a.tail == b.tail && a.warned == b.warned
    }
}

public struct WinchState: Equatable, Sendable {
    public var pointIndex: Int
    public var personID: Int
    /// 0...1 until the person is aboard.
    public var progress: Double
    public var steady: Bool
    /// Length of the cable, from the helicopter down to the ledge.
    public var cable: Double
}

/// Deterministic pseudo-random number in 0..<1 from two integers (tests and replays repeat exactly).
func hazardRandom(_ a: Int, _ b: Int) -> Double {
    let v = sin(Double(a) * 12.9898 + Double(b) * 78.233) * 43758.5453
    return v - v.rounded(.down)
}

/// Ballistic path of a flying object: points every `dt` until it reaches `groundY` or `maxSteps`.
public func ballisticPath(_ o: FlyingObject, ground: (Double) -> Double, dt: Double = 0.1, maxSteps: Int = 80) -> [(x: Double, y: Double)] {
    var x = o.x, y = o.y, vx = o.vx, vy = o.vy
    var out: [(Double, Double)] = [(x, y)]
    for _ in 0..<maxSteps {
        vy -= o.gravity * dt
        x += vx * dt; y += vy * dt
        out.append((x, y))
        if y <= ground(x) { break }
    }
    return out
}

/// Everything the hazard building blocks keep track of while a mission runs.
public struct HazardState: Equatable, Sendable {
    public var strikes: [Strike] = []
    public var objects: [FlyingObject] = []
    public var rubble: [Rubble] = []
    public var flows: [FlowState]
    /// Per rescue point: time until which it is unusable (0 = free).
    public var blockedUntil: [Double]
    public var winch: WinchState?
    /// Shaking of the ground, 0...1 (aftershock, eruption).
    public var tremor = 0.0
    var nextStrike: [Int]
    var spawned: [Int]
    var warnedGroup: [Int]
    var flowPointWarned: Set<Int> = []
    var winchProgress: [Double]
    var winchHolding = false
    var flowHurtTimer = 0.0
    var refuelSaid = false
    var passageContactCooldown = 0.0
    var obstacleCooldown = 0.0
    var weatherWarned: Set<Int> = []
    var shutterWarnCycle: [Int: Int] = [:]
    var shutterCloseCycle: [Int: Int] = [:]
    var nextID = 0

    init(mission: Mission) {
        flows = Array(repeating: FlowState(), count: mission.flowList.count)
        blockedUntil = Array(repeating: 0, count: mission.rescuePoints.count)
        nextStrike = Array(repeating: 0, count: mission.stormList.count)
        spawned = Array(repeating: 0, count: mission.volleyList.count)
        warnedGroup = Array(repeating: -1, count: mission.volleyList.count)
        winchProgress = Array(repeating: 0, count: mission.rescuePoints.count)
    }
}
