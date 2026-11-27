import Foundation

// Endless mode: Einsätze put together by chance from the building blocks of the six Einsätze, one after another,
// ever harder, with a limited stock of helicopters over the whole run. Design: docs/planung/06 Abwechslung 0.7.md ("Detailentwurf 0.7b").
//
// A run is fixed by its seed: the same seed gives the same sequence of Einsätze (also for tests and for sharing a run).
// Adding a building block later (e.g. `obstacles`, `weather` of 0.7a): append it to `EndlessKit.blocks`, nothing else.

/// Small deterministic generator (SplitMix64), so seeds give the same Einsätze on every machine.
public struct SeededRandom: Sendable {
    private var state: UInt64
    public init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    public mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    /// 0..<1
    public mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    public mutating func double(_ r: ClosedRange<Double>) -> Double { r.lowerBound + (r.upperBound - r.lowerBound) * unit() }
    public mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
    public mutating func shuffled<T>(_ a: [T]) -> [T] {
        var a = a
        if a.count > 1 { for i in stride(from: a.count - 1, to: 0, by: -1) { a.swapAt(i, int(0...i)) } }
        return a
    }
}

/// One building block the generator may add to an Einsatz.
public struct EndlessBlock: Sendable {
    public var id: String
    /// First stage it may appear on.
    public var minStage: Int
    /// Whether it makes sense for this Einsatz (checked before it is chosen).
    public var fits: @Sendable (Mission) -> Bool
    /// Adds the block; `pressure` runs from 0 (stage 1) to 1 (stage 12 and later).
    public var apply: @Sendable (inout Mission, inout SeededRandom, Double) -> Void
}

public extension Mission {
    /// Something keeps coming (lava, fire, rising water): the Einsatz is tuned to the clock and takes little extra.
    var hasClock: Bool { !flowList.isEmpty || fire != nil || flood.risePerSecond > 0 }
}

public enum EndlessKit {
    /// The Einsätze that serve as the ground for a stage (terrain, rescue points, look). Central list: new Einsätze join here.
    public static var bases: [String] { MissionLibrary.all }

    /// The stretch between the last rescue point and the camp: a hazard from the sky that sits there threatens every
    /// transit but never the work on a pad (the scripted pilot, and a human, would be driven off the pads otherwise).
    private static func transitSpan(_ m: Mission, maxWidth: Double, _ rng: inout SeededRandom) -> (Double, Double)? {
        let lo = (m.rescuePoints.map { $0.x + $0.width / 2 }.max() ?? 0) + 260
        let hi = m.base.x - m.base.width / 2 - 200
        guard hi - lo >= 600 else { return nil }
        let width = min(hi - lo, maxWidth)
        let x0 = rng.double(lo...(hi - width))
        if m.passageList.contains(where: { $0.x1 + 220 > x0 && $0.x0 - 220 < x0 + width }) { return nil }
        return (x0, x0 + width)
    }

    public static let blocks: [EndlessBlock] = [
        EndlessBlock(id: "storm", minStage: 2,
                     fits: { $0.stormList.count < 3 && $0.rescuePoints.count > 0 && !$0.hasClock && $0.volleyList.isEmpty
                         && !$0.weatherList.contains { $0.kind == "thunder" } },
                     apply: { m, rng, p in
            guard let (x0, x1) = transitSpan(m, maxWidth: rng.double(900...1500), &rng) else { return }
            m.storms = (m.storms ?? []) + [StormCell(x0: x0, x1: x1, start: rng.double(25...45), interval: 17 - 5 * p,
                                                warn: 3.0 - 0.5 * p, radius: 150, damage: 14 + 6 * p)]
        }),
        // Weather of 0.7a (fog bank, wind shift). Obstacles (`obstacles`) are not added: every ground already brings its own,
        // placed with room around pads and passages, and more of them were not solvable for the scripted pilot. They sit on the transit stretch (`transitSpan`).
        EndlessBlock(id: "fogBank", minStage: 3,
                     fits: { !$0.weatherList.contains { $0.kind == "fog" } },
                     apply: { m, rng, p in
            guard let (x0, x1) = transitSpan(m, maxWidth: rng.double(900...1500), &rng) else { return }
            m.weather = m.weatherList + [WeatherEvent(kind: "fog", start: rng.double(60...(max(61, m.timeLimit * 0.5))), duration: rng.double(45...70),
                                                       warn: 8, density: 0.35 + 0.2 * p, x0: x0, x1: x1)]
        }),
        EndlessBlock(id: "windShift", minStage: 4,
                     fits: { $0.passageList.isEmpty && $0.fire == nil && !$0.rescuePoints.contains { $0.isWinch } },
                     apply: { m, rng, p in
            let sign: Double = rng.unit() < 0.5 ? -1 : 1
            m.weather = m.weatherList + [WeatherEvent(kind: "windShift", start: rng.double(60...(max(61, m.timeLimit * 0.6))), duration: rng.double(35...55),
                                                       warn: 8, strength: sign * rng.double(20...(30 + 15 * p)))]
        }),
        EndlessBlock(id: "gusts", minStage: 1,
                     fits: { _ in true },
                     apply: { m, rng, p in
            for _ in 0..<rng.int(1...2) {
                let sign: Double = rng.unit() < 0.5 ? -1 : 1
                m.wind.gusts.append(GustSpec(start: rng.double(30...(m.timeLimit * 0.7)), duration: rng.double(6...9),
                                             strength: sign * rng.double(30...(40 + 15 * p)) * (m.hasClock ? 0.6 : 1)))
            }
        }),
        // Icing: back to the camp to thaw now and then (not where the clock runs or doors wait).
        EndlessBlock(id: "icing", minStage: 5,
                     fits: { $0.icing == nil && !$0.hasClock && $0.passageList.isEmpty },
                     apply: { m, _, p in m.icing = IcingSpec(rate: 0.005 + 0.003 * p, thaw: 0.25, start: 20) }),
        // Not where fuel is already the bottleneck (outposts, the high mountains).
        EndlessBlock(id: "thirstyEngine", minStage: 3,
                     fits: { $0.outpostList.isEmpty && $0.hazard != "avalanche" && !$0.hasClock },
                     apply: { m, rng, p in m.fuel.burnPerSecond *= 1 + rng.double(0.03...(0.05 + 0.05 * p)) }),
    ]

    public static func block(_ id: String) -> EndlessBlock? { blocks.first { $0.id == id } }
}

public enum EndlessGenerator {
    /// Stage at which pressure and number of blocks stop growing.
    public static let plateauStage = 12

    /// The base Einsatz of a stage: the six in a seeded order, a new order after each round, never the same twice in a row.
    public static func baseID(seed: UInt64, stage: Int) -> String {
        let bases = EndlessKit.bases
        func order(_ cycle: Int) -> [String] {
            var r = SeededRandom(seed: seed &+ UInt64(cycle) &* 7919)
            return r.shuffled(bases)
        }
        let i = max(0, stage - 1), cycle = i / bases.count, k = i % bases.count
        var o = order(cycle)
        if cycle > 0, o[0] == order(cycle - 1).last { o.swapAt(0, 1) }
        return o[k]
    }

    /// Level of the data scaling for a stage: easy, then medium, then hard. The chosen level of the run shifts
    /// the whole ramp (medium: unchanged, beginner two steps easier, pro two steps harder).
    public static func level(stage: Int, chosen: Difficulty = .medium) -> Difficulty {
        let ramp: Difficulty = stage <= 2 ? .easy : (stage <= 5 ? .medium : .hard)
        return ramp.shifted(by: chosen.rank - Difficulty.medium.rank)
    }

    /// Growth from 0 (stage 1) to 1 (plateau).
    public static func pressure(stage: Int) -> Double { min(1, Double(max(1, stage) - 1) / Double(plateauStage - 1)) }

    /// Extra pressure beyond "hard" once the run goes on past stage 8: a little less time, harder hits. Fuel and water stay as they are.
    static func overdrive(stage: Int) -> Double { min(0.5, 0.04 * Double(max(0, stage - 8))) }

    /// The Einsatz of a stage. `helicopters` is what is left of the stock; `base` forces the ground (for tests).
    public static func mission(seed: UInt64, stage: Int, helicopters: Int, base forced: String? = nil,
                               level chosen: Difficulty = .medium) throws -> Mission {
        try generate(seed: seed, stage: stage, helicopters: helicopters, base: forced, level: chosen).mission
    }

    /// Like `mission`, with the ids of the building blocks that were added (for the stage card and for diagnosis).
    public static func generate(seed: UInt64, stage: Int, helicopters: Int, base forced: String? = nil,
                                level chosen: Difficulty = .medium,
                                skipping skipped: Set<String> = []) throws -> (mission: Mission, blocks: [String]) {
        let stage = max(1, stage)
        var rng = SeededRandom(seed: seed &* 31 &+ UInt64(stage) &* 0x2545_F491)
        let baseID = forced ?? Self.baseID(seed: seed, stage: stage)
        var m = try MissionLibrary.load(baseID)
        let p = pressure(stage: stage)
        let basePeople = max(1, m.totalPeople)

        // Rescue points: keep most, change the number of people. Where something keeps coming (lava, fire, rising water)
        // the points stay as designed, and the work never grows beyond what the original allows.
        let clock = !m.flowList.isEmpty || m.fire != nil || m.flood.risePerSecond > 0
        if m.rescuePoints.count > 3, !clock {
            let drop = rng.int(0...(m.rescuePoints.count - 3) / 2 + (m.rescuePoints.count > 5 ? 1 : 0))
            let removed = Set(rng.shuffled(Array(m.rescuePoints.indices)).prefix(drop))
            m.rescuePoints = m.rescuePoints.enumerated().filter { !removed.contains($0.offset) }.map(\.element)
        }
        let more = 1 + 0.03 * Double(stage - 1)
        // Rising water: the people stay as designed (the order of the pads is tuned to the rising level).
        for i in m.rescuePoints.indices where m.flood.risePerSecond == 0 {
            let n = Double(m.rescuePoints[i].people) * rng.double(0.7...1.4) * more
            m.rescuePoints[i].people = max(1, min(6, Int(n.rounded())))
        }
        if clock {
            while m.totalPeople > basePeople, let i = m.rescuePoints.indices.max(by: { m.rescuePoints[$0].people < m.rescuePoints[$1].people }),
                  m.rescuePoints[i].people > 1 {
                m.rescuePoints[i].people -= 1
            }
        }
        // Time follows the work: fewer people, less time; the stage tightens it.
        let ratio = Double(m.totalPeople) / Double(basePeople)
        m.timeLimit = (m.timeLimit * (0.55 + 0.45 * min(1.3, ratio))).rounded()
        // The gusts of the original Einsatz shift a little.
        m.wind.gusts = m.wind.gusts.map { var g = $0; g.start = max(10, g.start + rng.double(-25...25)); return g }

        // Building blocks: more of them the later the stage.
        let want = min(m.hasClock ? 2 : 4, 1 + Int((p * 3).rounded()))
        var pool = rng.shuffled(EndlessKit.blocks.filter { $0.minStage <= stage && $0.fits(m) })
        var applied: [String] = []
        while applied.count < want, !pool.isEmpty {
            let b = pool.removeFirst()
            // A block that makes the data invalid is dropped (and not counted).
            var trial = m
            b.apply(&trial, &rng, p)
            guard (try? trial.validate()) != nil else { continue }
            // `skipped` (diagnosis only): the random numbers were used, so the other blocks stay as they were.
            if !skipped.contains(b.id) { m = trial }
            applied.append(b.id)
        }

        // Fighting fires burns fuel far from the camp: a bigger tank there (the endless Einsätze have no outposts to land at).
        if m.fire != nil { m.fuel.capacity *= 1.35 }
        m = m.scaled(for: level(stage: stage, chosen: chosen))
        let od = overdrive(stage: stage)
        if od > 0 {
            m.timeLimit = (m.timeLimit * (1 - 0.25 * od)).rounded()
            m.storms = m.storms?.map { var s = $0; s.damage *= 1 + od; return s }
            m.volleys = m.volleys?.map { var v = $0; v.damage *= 1 + od; return v }
        }
        m.helicopters = max(1, helicopters)
        m.number = stage
        m.tagline = "Endlos · Stufe \(stage)"
        m.summary = nil
        try m.validate()
        return (m, applied)
    }
}

/// One run of the endless mode over many stages.
public struct EndlessRun: Equatable, Sendable {
    /// Stock at the start and its limit on medium.
    public static let startHelicopters = 5
    public static let maxHelicopters = 6

    /// Stock at the start of a run on a level.
    public static func startHelicopters(_ level: Difficulty) -> Int { startHelicopters - (level.rank - Difficulty.medium.rank) }
    /// Every this many cleared stages one helicopter joins the stock.
    public static let bonusEvery = 3
    public static let stageBonusPerStage = 50

    public enum Next: Equatable, Sendable {
        /// Next stage; `bonusHelicopter`: the stock grew by one.
        case next(bonusHelicopter: Bool)
        case over
    }

    public let seed: UInt64
    public let level: Difficulty
    public var startStock: Int { Self.startHelicopters(level) }
    public var stockLimit: Int { startStock + (Self.maxHelicopters - Self.startHelicopters) }
    /// The stage that is flown now (or was flown last when the run is over).
    public private(set) var stage = 1
    public private(set) var helicopters = EndlessRun.startHelicopters
    public private(set) var score = 0
    /// Stages cleared so far (the one that ended the run does not count).
    public private(set) var stagesCleared = 0
    public private(set) var isOver = false

    public init(seed: UInt64, level: Difficulty = .medium) {
        self.seed = seed
        self.level = level
        self.helicopters = Self.startHelicopters(level)
    }

    public func mission() throws -> Mission {
        try EndlessGenerator.mission(seed: seed, stage: stage, helicopters: helicopters, level: level)
    }

    /// A stage is cleared with at least one star (half of the people rescued) and a helicopter left.
    @discardableResult
    public mutating func finish(_ r: MissionResult) -> Next {
        guard !isOver else { return .over }
        score += r.score
        helicopters = max(0, helicopters - r.helicoptersLost)
        guard r.outcome != .failed, r.stars >= 1, helicopters > 0 else { isOver = true; return .over }
        stagesCleared += 1
        score += Self.stageBonusPerStage * stage
        stage += 1
        var bonus = false
        if stagesCleared % Self.bonusEvery == 0, helicopters < stockLimit { helicopters += 1; bonus = true }
        return .next(bonusHelicopter: bonus)
    }
}
