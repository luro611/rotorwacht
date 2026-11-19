import Foundation

public enum PersonState: Equatable, Sendable {
    case waiting
    case boarding   // walking to the helicopter, `progress` 0...1
    case aboard
    case leaving    // walking from the helicopter to the camp
    case rescued
    case lost       // taken by the flood
    case injured    // was aboard when the helicopter went down
}

public struct Person: Equatable, Sendable {
    public var id: Int
    public var pointIndex: Int
    /// Where the person waits (world x).
    public var spotX: Double
    public var state: PersonState = .waiting
    public var progress = 0.0
}

public enum SimEvent: Equatable, Sendable {
    case physics(PhysicsEvent)
    case boarded(personID: Int)
    case rescued(personID: Int)
    case lost(personID: Int, pointIndex: Int)
    case floodWarning(pointIndex: Int)
    case cabinFull
    case helicopterLost(remaining: Int)
    case respawned
    case finished
}

public enum MissionOutcome: Equatable, Sendable {
    case completed   // everybody is resolved
    case timeUp
    case failed      // no helicopters left
}

public struct MissionResult: Equatable, Sendable {
    public var outcome: MissionOutcome
    public var total: Int
    public var rescued: Int
    public var lost: Int
    public var injured: Int
    public var timeUsed: Double
    public var helicoptersLost: Int
    public var score: Int
    public var stars: Int

    public init(outcome: MissionOutcome, total: Int, rescued: Int, lost: Int, injured: Int, timeUsed: Double,
                helicoptersLost: Int, score: Int, stars: Int) {
        self.outcome = outcome; self.total = total; self.rescued = rescued; self.lost = lost
        self.injured = injured; self.timeUsed = timeUsed; self.helicoptersLost = helicoptersLost
        self.score = score; self.stars = stars
    }
}

public enum SimPhase: Equatable, Sendable {
    case flying
    /// Helicopter destroyed; waiting before the replacement arrives.
    case crashed(timeLeft: Double)
    case finished(MissionResult)
}

public struct MissionSimulation {
    public static let boardInterval = 0.6
    public static let walkTime = 0.8
    public static let crashDelay = 2.5
    public static let finishDelay = 1.5
    public static let repairPerSecond = 1.5

    public let mission: Mission
    public let spec: HelicopterSpec
    public private(set) var heli: HelicopterState
    public private(set) var people: [Person]
    public private(set) var time = 0.0
    public private(set) var floodLevel: Double
    public private(set) var wind = 0.0
    /// Helicopters still available, the one in use included.
    public private(set) var helicoptersLeft: Int
    public private(set) var phase: SimPhase = .flying
    private var boardTimer = 0.0
    private var disembarkTimer = 0.0
    private var finishTimer: Double?
    private var warned: Set<Int> = []
    private var cabinFullSent = false

    public init(mission: Mission, spec: HelicopterSpec = .standard) {
        self.mission = mission
        self.spec = spec
        self.floodLevel = mission.floodLevel(at: 0)
        self.helicoptersLeft = mission.helicopters
        self.heli = HelicopterState(
            x: mission.base.x, y: mission.baseSurface,
            fuel: mission.fuel.capacity, durability: spec.maxDurability)
        var list: [Person] = []
        var id = 0
        for (pi, p) in mission.rescuePoints.enumerated() {
            let usable = max(0, p.width - 40)
            for k in 0..<p.people {
                let offset = p.people == 1 ? 0 : (Double(k) + 0.5) / Double(p.people) * usable - usable / 2
                list.append(Person(id: id, pointIndex: pi, spotX: p.x + offset))
                id += 1
            }
        }
        self.people = list
    }

    // MARK: Queries

    public var aboardCount: Int { people.filter { $0.state == .aboard || $0.state == .boarding }.count }
    public var rescuedCount: Int { people.filter { $0.state == .rescued || $0.state == .leaving }.count }
    public var lostCount: Int { people.filter { $0.state == .lost }.count }
    public var injuredCount: Int { people.filter { $0.state == .injured }.count }
    public var timeLeft: Double { max(0, mission.timeLimit - time) }
    public var isFinished: Bool { if case .finished = phase { return true } else { return false } }
    public var result: MissionResult? { if case .finished(let r) = phase { return r } else { return nil } }
    public var inBaseZone: Bool { abs(heli.x - mission.base.x) <= mission.base.width / 2 }

    /// Index of the rescue point the landed helicopter stands on, if any.
    public func rescuePointUnderHelicopter() -> Int? {
        guard heli.onGround, !heli.inWater else { return nil }
        for (i, p) in mission.rescuePoints.enumerated() where abs(heli.x - p.x) <= p.width / 2 + 20 {
            return i
        }
        return nil
    }

    // MARK: Step

    @discardableResult
    public mutating func step(input: PilotInput, dt: Double) -> [SimEvent] {
        if isFinished { return [] }
        var events: [SimEvent] = []
        time += dt
        floodLevel = mission.floodLevel(at: time)
        wind = mission.windAcceleration(at: time)

        updateFlood(&events)

        switch phase {
        case .crashed(let left):
            let l = left - dt
            if l <= 0 { respawn(&events) } else { phase = .crashed(timeLeft: l) }
        case .flying:
            stepHelicopter(input: input, dt: dt, &events)
        case .finished:
            break
        }

        updatePeopleProgress(dt: dt, &events)
        checkFinish(dt: dt, &events)
        return events
    }

    private mutating func stepHelicopter(input: PilotInput, dt: Double, _ events: inout [SimEvent]) {
        let pe = HelicopterPhysics.step(
            &heli, input: input, dt: dt, wind: wind, waterLevel: floodLevel,
            mission: mission, fuelBurnPerSecond: mission.fuel.burnPerSecond, spec: spec)
        events += pe.map { .physics($0) }

        if heli.durability <= 0 {
            crash(&events)
            return
        }

        let landed = heli.onGround && !heli.inWater && abs(heli.vx) < 1
        if !landed {
            // Lifting off interrupts walking.
            for i in people.indices {
                if people[i].state == .boarding { people[i].state = .waiting; people[i].progress = 0 }
                if people[i].state == .leaving { people[i].state = .aboard; people[i].progress = 0 }
            }
            boardTimer = 0
            disembarkTimer = 0
            return
        }

        if inBaseZone {
            heli.fuel = min(mission.fuel.capacity, heli.fuel + mission.fuel.refuelPerSecond * dt)
            heli.durability = min(spec.maxDurability, heli.durability + Self.repairPerSecond * dt)
            disembarkTimer += dt
            if disembarkTimer >= Self.boardInterval,
               let i = people.firstIndex(where: { $0.state == .aboard }) {
                people[i].state = .leaving
                people[i].progress = 0
                disembarkTimer = 0
            }
            cabinFullSent = false
        } else if let pi = rescuePointUnderHelicopter() {
            boardTimer += dt
            if boardTimer >= Self.boardInterval {
                if aboardCount < mission.capacity {
                    if let i = people.firstIndex(where: { $0.pointIndex == pi && $0.state == .waiting }) {
                        people[i].state = .boarding
                        people[i].progress = 0
                        boardTimer = 0
                    }
                } else if !cabinFullSent,
                          people.contains(where: { $0.pointIndex == pi && $0.state == .waiting }) {
                    cabinFullSent = true
                    events.append(.cabinFull)
                }
            }
        }
    }

    private mutating func updatePeopleProgress(dt: Double, _ events: inout [SimEvent]) {
        for i in people.indices {
            switch people[i].state {
            case .boarding:
                people[i].progress += dt / Self.walkTime
                if people[i].progress >= 1 {
                    people[i].state = .aboard
                    people[i].progress = 0
                    events.append(.boarded(personID: people[i].id))
                }
            case .leaving:
                people[i].progress += dt / Self.walkTime
                if people[i].progress >= 1 {
                    people[i].state = .rescued
                    people[i].progress = 0
                    events.append(.rescued(personID: people[i].id))
                }
            default: break
            }
        }
    }

    private mutating func updateFlood(_ events: inout [SimEvent]) {
        for (pi, p) in mission.rescuePoints.enumerated() {
            let hasPeopleThere = people.contains { $0.pointIndex == pi && ($0.state == .waiting || $0.state == .boarding) }
            guard hasPeopleThere else { continue }
            if floodLevel > p.top + 8 {
                for i in people.indices where people[i].pointIndex == pi
                    && (people[i].state == .waiting || people[i].state == .boarding) {
                    people[i].state = .lost
                    events.append(.lost(personID: people[i].id, pointIndex: pi))
                }
            } else if floodLevel > p.top - 35, !warned.contains(pi) {
                warned.insert(pi)
                events.append(.floodWarning(pointIndex: pi))
            }
        }
    }

    private mutating func crash(_ events: inout [SimEvent]) {
        helicoptersLeft -= 1
        for i in people.indices where people[i].state == .aboard || people[i].state == .boarding
            || people[i].state == .leaving {
            // Those already stepping out at the camp count as rescued; the rest are injured.
            people[i].state = people[i].state == .leaving ? .rescued : .injured
            people[i].progress = 0
        }
        events.append(.helicopterLost(remaining: helicoptersLeft))
        if helicoptersLeft <= 0 {
            finish(.failed, &events)
        } else {
            phase = .crashed(timeLeft: Self.crashDelay)
        }
    }

    private mutating func respawn(_ events: inout [SimEvent]) {
        heli = HelicopterState(
            x: mission.base.x, y: mission.baseSurface,
            fuel: mission.fuel.capacity, durability: spec.maxDurability)
        boardTimer = 0
        disembarkTimer = 0
        phase = .flying
        events.append(.respawned)
    }

    private mutating func checkFinish(dt: Double, _ events: inout [SimEvent]) {
        if isFinished { return }
        let open = people.contains { [.waiting, .boarding, .aboard, .leaving].contains($0.state) }
        if !open {
            finishTimer = (finishTimer ?? Self.finishDelay) - dt
            if let t = finishTimer, t <= 0 { finish(.completed, &events) }
        } else if time >= mission.timeLimit {
            // Whoever is still aboard at the horn is counted as not rescued.
            for i in people.indices where people[i].state == .aboard { people[i].state = .injured }
            finish(.timeUp, &events)
        }
    }

    private mutating func finish(_ outcome: MissionOutcome, _ events: inout [SimEvent]) {
        let total = people.count
        let rescued = rescuedCount
        let lost = lostCount
        let injured = injuredCount + people.filter { [.waiting, .aboard, .boarding].contains($0.state) }.count
        let heliLost = mission.helicopters - helicoptersLeft
        var score = rescued * 100 - heliLost * 50
        if outcome == .completed { score += Int(timeLeft) }
        score = max(0, score)
        var stars = 0
        let ratio = total == 0 ? 1.0 : Double(rescued) / Double(total)
        if ratio >= 0.5 { stars = 1 }
        if ratio >= 0.8 { stars = 2 }
        if rescued == total && heliLost == 0 { stars = 3 }
        let result = MissionResult(
            outcome: outcome, total: total, rescued: rescued, lost: lost, injured: injured,
            timeUsed: min(time, mission.timeLimit), helicoptersLost: heliLost, score: score, stars: stars)
        phase = .finished(result)
        events.append(.finished)
    }
}

// MARK: - Test hooks

extension MissionSimulation {
    /// For tests: put the helicopter somewhere.
    public mutating func debugPlaceHelicopter(_ state: HelicopterState) { heli = state }

    /// For tests: move people aboard instead of picking them up.
    public mutating func debugSetPeople(aboard count: Int) {
        var n = people.count
        for _ in 0..<count {
            people.append(Person(id: n, pointIndex: 0, spotX: 0, state: .aboard))
            n += 1
        }
    }
}
