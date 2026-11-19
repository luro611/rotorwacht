import Foundation

/// One stretch of ground (`cellWidth` wide) that can burn.
public struct FireCell: Equatable, Sendable {
    /// Fuel left, 0...1. A cell without fuel (water, rock, ash) cannot burn.
    public var fuel: Double
    /// 0 = not burning, 1 = fully ablaze.
    public var intensity = 0.0
    /// Progress towards catching fire from neighbours, 0...1.
    public var heat = 0.0
    /// Dampness from water; at 1 or more the cell cannot catch fire.
    public var wet = 0.0
    /// Has burned at some time (drawn as scorched ground).
    public var charred = false

    public var burning: Bool { intensity > 0 }
}

/// A droplet of extinguishing water in flight. Carries the helicopter's speed when released.
public struct WaterDrop: Equatable, Sendable {
    public var id: Int
    public var x: Double
    public var y: Double
    public var vx: Double
    public var vy: Double
}

/// Fire on the ground: spreads from burning cells to their neighbours (faster uphill and downwind),
/// burns out, and is put out or held back by water. Deterministic, so tests and replays repeat exactly.
public struct FireField: Sendable {
    public static let spreadReach = 3
    public static let dropRadius = 48.0
    public static let dropStrength = 0.30
    public static let dropWetting = 0.30
    public static let wetDecayPerSecond = 0.035
    public static let growthPerSecond = 0.28
    /// How strongly water makes a wet burning cell lose intensity per second.
    public static let wetSuppression = 0.35

    public let spec: FireSpec
    public private(set) var cells: [FireCell]
    /// Burning cells put out with water so far.
    public private(set) var extinguishedCount = 0
    private var done: Set<Int> = []
    private let groundHeights: [Double]

    public init(mission: Mission) {
        let spec = mission.fire ?? FireSpec(cellWidth: 40, burnTime: 30, spreadRate: 0.4, zones: [], ignitions: [])
        self.spec = spec
        let count = max(1, Int((mission.world.width / spec.cellWidth).rounded(.up)))
        var list: [FireCell] = []
        var heights: [Double] = []
        for i in 0..<count {
            let x = (Double(i) + 0.5) * spec.cellWidth
            let fuel = spec.zones.filter { x >= $0.x0 && x <= $0.x1 }.map(\.fuel).max() ?? 0
            list.append(FireCell(fuel: fuel))
            heights.append(mission.groundHeight(at: x))
        }
        cells = list
        groundHeights = heights
        // Fires that exist from the start.
        for (k, ig) in spec.ignitions.enumerated() where ig.time <= 0 {
            ignite(at: ig.x, intensity: ig.intensity)
            done.insert(k)
        }
    }

    public var cellWidth: Double { spec.cellWidth }
    public func center(of i: Int) -> Double { (Double(i) + 0.5) * spec.cellWidth }
    public func index(at x: Double) -> Int? {
        let i = Int((x / spec.cellWidth).rounded(.down))
        return cells.indices.contains(i) ? i : nil
    }
    public var burningCount: Int { cells.reduce(0) { $0 + ($1.burning ? 1 : 0) } }
    public var hasPendingIgnitions: Bool { done.count < spec.ignitions.count }
    public func groundHeight(of i: Int) -> Double { groundHeights[i] }

    /// Strongest fire in a span of x positions.
    public func maxIntensity(from x0: Double, to x1: Double) -> Double {
        guard let a = index(at: max(0, x0)), let b = index(at: min(x1, Double(cells.count) * spec.cellWidth - 1)) else { return 0 }
        var m = 0.0
        if a <= b { for i in a...b { m = max(m, cells[i].intensity) } }
        return m
    }

    /// Sets a cell alight (if it can burn).
    public mutating func ignite(at x: Double, intensity: Double) {
        guard let i = index(at: x), cells[i].fuel > 0, cells[i].wet < 1 else { return }
        cells[i].intensity = max(cells[i].intensity, min(1, max(0.05, intensity)))
        cells[i].heat = 0
        cells[i].charred = true
    }

    /// Water strikes the ground at x: cools and dampens the cells around it.
    public mutating func douse(at x: Double) {
        let r = Self.dropRadius
        guard let lo = index(at: max(0, x - r)), let hi = index(at: min(x + r, Double(cells.count) * spec.cellWidth - 1)) else { return }
        for i in lo...hi {
            let d = abs(center(of: i) - x)
            if d > r + spec.cellWidth / 2 { continue }
            let w = max(0.25, 1 - d / (r + spec.cellWidth / 2) * 0.7)
            cells[i].wet = min(1.5, cells[i].wet + Self.dropWetting * w)
            cells[i].heat = 0
            if cells[i].intensity > 0 {
                cells[i].intensity -= Self.dropStrength * w
                if cells[i].intensity <= 0.02 {
                    cells[i].intensity = 0
                    extinguishedCount += 1
                }
            }
        }
    }

    /// Advances the fire. Returns the x positions of fires that newly broke out on schedule.
    @discardableResult
    public mutating func step(dt: Double, time: Double, wind: Double) -> [Double] {
        var started: [Double] = []
        for (k, ig) in spec.ignitions.enumerated() where !done.contains(k) && time >= ig.time {
            done.insert(k)
            ignite(at: ig.x, intensity: ig.intensity)
            started.append(ig.x)
        }

        let src = cells.map(\.intensity)
        let windN = max(-1, min(1, wind / 200))
        let n = cells.count
        for i in 0..<n {
            var c = cells[i]
            c.wet = max(0, c.wet - Self.wetDecayPerSecond * dt)
            if c.intensity > 0 {
                c.intensity = min(1, c.intensity + Self.growthPerSecond * dt)
                c.intensity -= c.wet * Self.wetSuppression * dt
                c.fuel -= dt / spec.burnTime * c.intensity
                if c.fuel <= 0 {
                    c.fuel = 0
                    c.intensity = 0
                } else if c.intensity <= 0.02 {
                    c.intensity = 0
                    extinguishedCount += 1
                }
            } else if c.fuel > 0 {
                var incoming = 0.0
                for k in 1...Self.spreadReach {
                    let weight = k == 1 ? 1.0 : (k == 2 ? 0.45 : 0.15)
                    for dir in [-1, 1] {
                        let s = i + dir * k
                        guard s >= 0, s < n, src[s] > 0.2 else { continue }
                        // Direction of travel is from s to i.
                        let travel = Double(-dir)
                        let windFactor = 1 + 0.5 * windN * travel
                        let rise = (groundHeights[i] - groundHeights[s]) / (Double(k) * spec.cellWidth)
                        let slope = 1 + max(-0.5, min(2, rise * 3))
                        incoming += src[s] * weight * max(0.2, windFactor) * slope
                    }
                }
                if incoming > 0 {
                    c.heat += incoming * spec.spreadRate * dt * max(0, 1 - c.wet)
                    if c.heat >= 1 { c.heat = 0; c.intensity = 0.15; c.charred = true }
                } else {
                    c.heat = max(0, c.heat - 0.2 * dt)
                }
            }
            cells[i] = c
        }
        return started
    }

    /// Smoke density (0...1) at a point: dense near fire, thinner with distance and above the flames.
    public func smoke(atX x: Double, y: Double) -> Double {
        guard let lo = index(at: max(0, x - 320)), let hi = index(at: min(x + 320, Double(cells.count) * spec.cellWidth - 1)) else { return 0 }
        var total = 0.0
        for i in lo...hi where cells[i].intensity > 0 {
            let dx = abs(center(of: i) - x)
            let across = max(0, 1 - dx / 320)
            let height = max(0, min(1, 1 - (y - groundHeights[i] - 90) / 300))
            total += cells[i].intensity * across * height * 0.22
        }
        return min(1, total)
    }

    /// Burn damage rate (0...1) for something at a point.
    public func heat(atX x: Double, y: Double) -> Double {
        guard let lo = index(at: max(0, x - 90)), let hi = index(at: min(x + 90, Double(cells.count) * spec.cellWidth - 1)) else { return 0 }
        var h = 0.0
        for i in lo...hi where cells[i].intensity > 0.2 {
            let dx = abs(center(of: i) - x)
            if dx > 90 { continue }
            let reach = 40 + 110 * cells[i].intensity
            let up = y - groundHeights[i]
            if up > reach { continue }
            h = max(h, cells[i].intensity * (1 - up / reach) * (1 - dx / 90))
        }
        return max(0, h)
    }
}
