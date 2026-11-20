import Foundation

public enum PersonState: Equatable, Sendable {
    case waiting
    case boarding   // walking to the helicopter, `progress` 0...1
    case hoisting   // on the winch cable, `progress` 0...1
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
    case fireStarted(x: Double)
    case fireWarning(pointIndex: Int)
    case hurtByFire(personID: Int, pointIndex: Int)
    case scorched(damage: Double)
    case tankFull
    case tankEmpty
    case cabinFull
    case helicopterLost(remaining: Int)
    case respawned
    case finished
    // Hazard building blocks
    case strikeWarning(x: Double)
    case lightning(x: Double, hit: Bool)
    case tremor(kind: String, seconds: Double)
    case objectLaunched(kind: String)
    case impact(kind: String, x: Double, blockedPoint: Int?)
    case struckByObject(kind: String, damage: Double)
    case padBlocked(pointIndex: Int)
    case padCleared(pointIndex: Int)
    case flowWarning(flowIndex: Int, pointIndex: Int?)
    case flowStarted(flowIndex: Int)
    case flowScorched(flowIndex: Int)
    case winchStarted(pointIndex: Int)
    case winchSlipped
    case refueling
    // Passages
    case shutterWarning(passage: Int, shutter: Int)
    case shutterClosing(passage: Int, shutter: Int)
    case shutterCrush(passage: Int)
    case passageContact(kind: String, damage: Double)
    // Obstacles and weather
    case obstacleHit(kind: String, damage: Double, x: Double, y: Double)
    case weatherWarning(kind: String, seconds: Double)
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
    /// Seconds without fuel on firm ground outside the camp until the helicopter is written off.
    public static let strandedTime = 2.5
    public static let repairPerSecond = 1.5
    /// Highest height above the water at which the tank still fills.
    public static let skimHeight = 55.0
    public static let dropGravity = 620.0
    /// Seconds of fire exposure before waiting people are warned / hurt.
    public static let fireWarnTime = 4.0
    public static let fireHurtTime = 12.0
    public static let heatDamagePerSecond = 16.0

    public let mission: Mission
    public let spec: HelicopterSpec
    public internal(set) var heli: HelicopterState
    public internal(set) var people: [Person]
    public private(set) var time = 0.0
    public private(set) var floodLevel: Double
    public private(set) var wind = 0.0
    public private(set) var fire: FireField
    public private(set) var drops: [WaterDrop] = []
    /// Smoke at the helicopter (0...1): takes away sight.
    public private(set) var smoke = 0.0
    /// Heat at the helicopter (0...1): costs durability.
    public private(set) var heat = 0.0
    public private(set) var filling = false
    public private(set) var dropping = false
    /// Seconds each rescue point has been close to a fire (0 when safe).
    public private(set) var fireExposure: [Double]
    public internal(set) var hz: HazardState
    private var dropAccumulator = 0.0
    private var nextDropID = 0
    private var tankWasFull = true
    private var tankHadWater = true
    private var scorchTimer = 0.0
    private var fireWarned: Set<Int> = []
    /// Helicopters still available, the one in use included.
    public private(set) var helicoptersLeft: Int
    public private(set) var phase: SimPhase = .flying
    private var boardTimer = 0.0
    private var disembarkTimer = 0.0
    private var finishTimer: Double?
    private var warned: Set<Int> = []
    var cabinFullSent = false
    private var strandedTimer = 0.0

    public init(mission: Mission, spec: HelicopterSpec = .standard) {
        self.mission = mission
        self.spec = spec
        self.floodLevel = mission.floodLevel(at: 0)
        self.fire = FireField(mission: mission)
        self.hz = HazardState(mission: mission)
        self.fireExposure = Array(repeating: 0, count: mission.rescuePoints.count)
        self.helicoptersLeft = mission.helicopters
        let sx = mission.startX ?? mission.base.x
        self.heli = HelicopterState(
            x: sx, y: mission.surfaceHeight(at: sx),
            fuel: mission.fuel.capacity, durability: spec.maxDurability)
        self.heli.water = mission.tankSpec.capacity
        var list: [Person] = []
        var id = 0
        for (pi, p) in mission.rescuePoints.enumerated() {
            // The waiting stand at the two edges of the pad, clear of the skids, one after the other towards the middle.
            for k in 0..<p.people {
                list.append(Person(id: id, pointIndex: pi, spotX: p.x + Self.spotOffset(index: k, width: p.width)))
                id += 1
            }
        }
        self.people = list
    }

    /// Offset from the pad centre where person `index` waits: alternately left and right, outermost first.
    public static func spotOffset(index k: Int, width: Double) -> Double {
        let side: Double = k % 2 == 0 ? -1 : 1
        let step = Double(k / 2) * 13
        let edge = width / 2 - 14
        return side * max(edge - step, 20)
    }

    // MARK: Queries

    public var aboardCount: Int { people.filter { $0.state == .aboard || $0.state == .boarding || $0.state == .hoisting }.count }
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
        for (i, p) in mission.rescuePoints.enumerated() where !p.isWinch && abs(heli.x - p.x) <= p.width / 2 + spec.halfWidth {
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
        updateFire(dt: dt, &events)
        updateHazards(dt: dt, &events)

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
            &heli, input: input, dt: dt, wind: wind,
            waterLevel: mission.waterLevel(from: heli.x - spec.halfWidth, to: heli.x + spec.halfWidth, flood: floodLevel),
            mission: mission, fuelBurnPerSecond: mission.fuel.burnPerSecond, spec: spec)
        events += pe.map { .physics($0) }

        // Out of fuel on the ground away from the camp: no way to take off again, so write it off.
        if heli.fuel <= 0, heli.onGround, !inBaseZone, outpostUnderHelicopter() == nil {
            strandedTimer += dt
            if strandedTimer >= Self.strandedTime {
                strandedTimer = 0
                heli.durability = 0
                crash(&events)
                return
            }
        } else {
            strandedTimer = 0
        }

        stepTank(input: input, dt: dt, &events)
        applyHeat(dt: dt, &events)
        stepWinch(dt: dt, &events)
        stepPassages(dt: dt, &events)
        stepObstacles(dt: dt, &events)

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
            heli.water = min(mission.tankSpec.capacity, heli.water + mission.tankSpec.fillPerSecond * 1.5 * dt)
            disembarkTimer += dt
            if disembarkTimer >= Self.boardInterval,
               let i = people.firstIndex(where: { $0.state == .aboard }) {
                people[i].state = .leaving
                people[i].progress = 0
                disembarkTimer = 0
            }
            cabinFullSent = false
            hz.refuelSaid = false
        } else if let oi = outpostUnderHelicopter() {
            _ = oi
            heli.fuel = min(mission.fuel.capacity, heli.fuel + mission.fuel.refuelPerSecond * 0.8 * dt)
            if !hz.refuelSaid { hz.refuelSaid = true; events.append(.refueling) }
        } else if let pi = rescuePointUnderHelicopter(), !isBlocked(pi) {
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

    // MARK: Water and fire

    private mutating func stepTank(input: PilotInput, dt: Double, _ events: inout [SimEvent]) {
        let tank = mission.tankSpec
        // Fill by skimming low over open water (or sitting in it).
        let level = mission.waterLevel(from: heli.x - spec.halfWidth, to: heli.x + spec.halfWidth, flood: floodLevel)
        let surface = mission.maxSurface(from: heli.x - spec.halfWidth, to: heli.x + spec.halfWidth)
        let overWater = level > surface && heli.y - level < Self.skimHeight && heli.fuel > 0
        filling = overWater && heli.water < tank.capacity
        if filling { heli.water = min(tank.capacity, heli.water + tank.fillPerSecond * dt) }

        // Release: droplets inherit the helicopter's speed, so they fly on before they fall.
        dropping = false
        if input.drop, heli.water >= 1, !heli.onGround, heli.fuel > 0 {
            dropping = true
            dropAccumulator += tank.dropPerSecond * dt
            while dropAccumulator >= 1, heli.water >= 1 {
                dropAccumulator -= 1
                heli.water -= 1
                nextDropID += 1
                let n = Double(nextDropID)
                let jitter = sin(n * 12.9898) * 43758.5453
                let r = jitter - jitter.rounded(.down) - 0.5   // deterministic, -0.5...0.5
                drops.append(WaterDrop(
                    id: nextDropID,
                    x: heli.x + r * 36, y: heli.y + 6,
                    vx: heli.vx * 0.92 + r * 40, vy: heli.vy * 0.5 - 20))
            }
        } else {
            dropAccumulator = 0
        }
        if heli.water >= tank.capacity - 0.01 {
            if !tankWasFull { events.append(.tankFull) }
            tankWasFull = true
            tankHadWater = true
        } else {
            tankWasFull = false
            if heli.water < 1 {
                if tankHadWater { events.append(.tankEmpty) }
                tankHadWater = false
            } else {
                tankHadWater = true
            }
        }
    }

    private mutating func stepDrops(dt: Double) {
        guard !drops.isEmpty else { return }
        var alive: [WaterDrop] = []
        alive.reserveCapacity(drops.count)
        for var d in drops {
            d.vy -= Self.dropGravity * dt
            d.vx += (wind * 0.4 - d.vx * 0.35) * dt
            d.x += d.vx * dt
            d.y += d.vy * dt
            let ground = mission.surfaceHeight(at: d.x)
            var hitHeight = ground
            if let i = fire.index(at: d.x), fire.cells[i].burning { hitHeight += 20 + 50 * fire.cells[i].intensity }
            let waterLevel = mission.waterLevel(from: d.x, to: d.x, flood: floodLevel)
            if d.y <= max(hitHeight, waterLevel) {
                if waterLevel <= ground { fire.douse(at: d.x) }
            } else if d.x >= 0, d.x <= mission.world.width {
                alive.append(d)
            }
        }
        drops = alive
    }

    private mutating func updateFire(dt: Double, _ events: inout [SimEvent]) {
        for x in fire.step(dt: dt, time: time, wind: wind) { events.append(.fireStarted(x: x)) }
        stepDrops(dt: dt)
        guard mission.fire != nil else { return }

        // Waiting people near flames are in danger; they have time while the fire is still approaching.
        for (pi, p) in mission.rescuePoints.enumerated() {
            let near = fire.maxIntensity(from: p.x - p.width / 2 - 70, to: p.x + p.width / 2 + 70)
            if near > 0.25 { fireExposure[pi] += dt * near } else { fireExposure[pi] = max(0, fireExposure[pi] - dt) }
            if fireExposure[pi] < 1 { fireWarned.remove(pi) }
            let waiting = people.indices.filter {
                people[$0].pointIndex == pi && (people[$0].state == .waiting || people[$0].state == .boarding)
            }
            guard !waiting.isEmpty else { continue }
            if fireExposure[pi] >= Self.fireHurtTime {
                for i in waiting {
                    people[i].state = .injured
                    events.append(.hurtByFire(personID: people[i].id, pointIndex: pi))
                }
            } else if fireExposure[pi] >= Self.fireWarnTime, !fireWarned.contains(pi) {
                fireWarned.insert(pi)
                events.append(.fireWarning(pointIndex: pi))
            }
        }
        smoke = fire.smoke(atX: heli.x, y: heli.y)
    }

    private mutating func applyHeat(dt: Double, _ events: inout [SimEvent]) {
        guard mission.fire != nil else { heat = 0; return }
        heat = fire.heat(atX: heli.x, y: heli.y)
        guard heat > 0.02, !heli.onGround || heat > 0.1 else { return }
        let damage = Self.heatDamagePerSecond * heat * dt
        heli.durability = max(0, heli.durability - damage)
        scorchTimer -= dt
        if scorchTimer <= 0 { scorchTimer = 2.5; events.append(.scorched(damage: damage)) }
    }

    private mutating func crash(_ events: inout [SimEvent]) {
        if !mission.isPractice { helicoptersLeft -= 1 }
        for i in people.indices where people[i].state == .aboard || people[i].state == .boarding
            || people[i].state == .leaving || people[i].state == .hoisting {
            // Those already stepping out at the camp count as rescued; the rest are injured.
            people[i].state = people[i].state == .leaving ? .rescued : .injured
            people[i].progress = 0
        }
        // The cable goes down with the helicopter: no stale cable or winch bar while the replacement is on its way.
        hz.winchProgress = Array(repeating: 0, count: mission.rescuePoints.count)
        hz.winchHolding = false
        hz.winch = nil
        events.append(.helicopterLost(remaining: helicoptersLeft))
        if helicoptersLeft <= 0 {
            finish(.failed, &events)
        } else {
            phase = .crashed(timeLeft: mission.isPractice ? 0.4 : Self.crashDelay)
        }
    }

    private mutating func respawn(_ events: inout [SimEvent]) {
        let sx = mission.startX ?? mission.base.x
        heli = HelicopterState(
            x: sx, y: mission.surfaceHeight(at: sx),
            fuel: mission.fuel.capacity, durability: spec.maxDurability)
        heli.water = mission.tankSpec.capacity
        hz.winchProgress = Array(repeating: 0, count: mission.rescuePoints.count)
        hz.winchHolding = false
        hz.winch = nil
        boardTimer = 0
        disembarkTimer = 0
        phase = .flying
        events.append(.respawned)
    }

    private mutating func checkFinish(dt: Double, _ events: inout [SimEvent]) {
        if isFinished { return }
        let open = people.contains { [.waiting, .boarding, .aboard, .leaving, .hoisting].contains($0.state) }
        if !open {
            finishTimer = (finishTimer ?? Self.finishDelay) - dt
            if let t = finishTimer, t <= 0 { finish(.completed, &events) }
        } else if time >= mission.timeLimit {
            // Whoever is still aboard at the horn is counted as not rescued.
            for i in people.indices where people[i].state == .aboard || people[i].state == .hoisting { people[i].state = .injured }
            finish(.timeUp, &events)
        }
    }

    private mutating func finish(_ outcome: MissionOutcome, _ events: inout [SimEvent]) {
        let total = people.count
        let rescued = rescuedCount
        let lost = lostCount
        let injured = injuredCount + people.filter { [.waiting, .aboard, .boarding, .hoisting].contains($0.state) }.count
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
