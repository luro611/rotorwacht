import Foundation

// Hazard rules of MissionSimulation: lightning, falling and flying objects, ground flows, winch, outposts.

extension MissionSimulation {
    public static let winchTime = 3.2
    public static let winchTolerance = 38.0
    public static let winchMinHeight = 14.0
    public static let winchMaxSpeed = 30.0
    public static let strikeFlash = 0.5
    /// Radius of the helicopter body for hits by objects (around its middle).
    public static let bodyRadius = 34.0

    // MARK: Queries

    public func isBlocked(_ pointIndex: Int) -> Bool { hz.blockedUntil[pointIndex] > time }

    /// Outpost the landed helicopter stands on, if any.
    public func outpostUnderHelicopter() -> Int? {
        guard heli.onGround, !heli.inWater else { return nil }
        return mission.outpostList.firstIndex { abs(heli.x - $0.x) <= $0.width / 2 }
    }

    /// Ash in the air, 0...1.
    public var ash: Double { mission.ashDensity(at: time) }

    // MARK: Step

    mutating func updateHazards(dt: Double, _ events: inout [SimEvent]) {
        let alive: Bool = { if case .flying = phase { return true } else { return false } }()
        stepStorms(dt: dt, alive: alive, &events)
        stepVolleys(dt: dt, &events)
        stepObjects(dt: dt, alive: alive, &events)
        stepFlows(dt: dt, alive: alive, &events)
        stepPassageRhythm(dt: dt, &events)
        stepWeather(&events)
        for i in hz.blockedUntil.indices where hz.blockedUntil[i] > 0 && hz.blockedUntil[i] <= time {
            hz.blockedUntil[i] = 0
            events.append(.padCleared(pointIndex: i))
        }
        hz.rubble.removeAll { $0.until <= time }
    }

    // MARK: Lightning

    private mutating func stepStorms(dt: Double, alive: Bool, _ events: inout [SimEvent]) {
        for (ci, cell) in mission.stormList.enumerated() {
            let k = hz.nextStrike[ci]
            let at = cell.start + Double(k) * cell.interval
            if let u = cell.until, at > u { continue }
            if time >= at - cell.warn {
                hz.nextStrike[ci] += 1
                let r = hazardRandom(ci + 1, k + 1)
                let aimed = alive && k % 3 != 2 && heli.x >= cell.x0 - 200 && heli.x <= cell.x1 + 200
                let x = aimed ? min(cell.x1, max(cell.x0, heli.x + (r - 0.5) * cell.radius * 0.8)) : cell.x0 + r * (cell.x1 - cell.x0)
                hz.nextID += 1
                hz.strikes.append(Strike(id: hz.nextID, x: x, timeLeft: max(0, at - time), age: nil))
                events.append(.strikeWarning(x: x))
            }
        }
        for i in hz.strikes.indices {
            if hz.strikes[i].age != nil { hz.strikes[i].age! += dt; continue }
            hz.strikes[i].timeLeft -= dt
            if hz.strikes[i].timeLeft <= 0 {
                hz.strikes[i].age = 0
                let x = hz.strikes[i].x
                let cell = mission.stormList.first { x >= $0.x0 - 1 && x <= $0.x1 + 1 }
                var hit = false
                if alive, let c = cell, abs(heli.x - x) <= c.radius {
                    hit = true
                    heli.durability = max(0, heli.durability - c.damage)
                    events.append(.struckByObject(kind: "lightning", damage: c.damage))
                }
                events.append(.lightning(x: x, hit: hit))
            }
        }
        hz.strikes.removeAll { ($0.age ?? 0) > Self.strikeFlash }
    }

    // MARK: Falling and flying objects

    private mutating func stepVolleys(dt: Double, _ events: inout [SimEvent]) {
        var tremor = 0.0
        for (vi, v) in mission.volleyList.enumerated() {
            let total = v.repeats * v.count
            let n = hz.spawned[vi]
            guard n < total else { continue }
            let group = n / v.count
            let groupStart = v.start + Double(group) * v.interval
            if time >= groupStart - v.warn {
                if hz.warnedGroup[vi] < group {
                    hz.warnedGroup[vi] = group
                    events.append(.tremor(kind: v.kind, seconds: v.warn))
                }
                let lead = v.warn > 0 ? min(1, (time - (groupStart - v.warn)) / v.warn) : 1
                tremor = max(tremor, 0.3 + 0.7 * lead)
            }
            while hz.spawned[vi] < total {
                let k = hz.spawned[vi]
                let due = v.start + Double(k / v.count) * v.interval + Double(k % v.count) * v.stagger
                guard time >= due else { break }
                hz.spawned[vi] += 1
                let r1 = hazardRandom(vi + 7, k), r2 = hazardRandom(vi + 31, k + 5), r3 = hazardRandom(vi + 63, k + 11)
                let speed = v.speedMin + (v.speedMax - v.speedMin) * r2
                let a = (v.angleMin + (v.angleMax - v.angleMin) * r3) * Double.pi / 180
                hz.nextID += 1
                hz.objects.append(FlyingObject(
                    id: hz.nextID, kind: v.kind, x: v.x0 + (v.x1 - v.x0) * r1, y: v.spawnY,
                    vx: speed * cos(a), vy: speed * sin(a), gravity: v.gravity,
                    radius: v.radius, damage: v.damage, blockTime: v.blockTime))
                events.append(.objectLaunched(kind: v.kind))
            }
        }
        hz.tremor = tremor
    }

    private mutating func stepObjects(dt: Double, alive: Bool, _ events: inout [SimEvent]) {
        guard !hz.objects.isEmpty else { return }
        var keep: [FlyingObject] = []
        for var o in hz.objects {
            o.vy -= o.gravity * dt
            o.x += o.vx * dt
            o.y += o.vy * dt
            if o.x < 0 || o.x > mission.world.width { continue }
            // Over a passage the span is solid: what falls onto it is gone.
            if let pi = mission.passageIndex(at: o.x), o.y > mission.passageList[pi].roof { continue }
            if alive, hypot(o.x - heli.x, o.y - (heli.y + 30)) <= o.radius + Self.bodyRadius {
                heli.durability = max(0, heli.durability - o.damage)
                events.append(.struckByObject(kind: o.kind, damage: o.damage))
                continue
            }
            let ground = mission.surfaceHeight(at: o.x)
            if o.y <= ground {
                if mission.waterLevel(from: o.x, to: o.x, flood: floodLevel) > ground { continue }
                landObject(o, events: &events)
                continue
            }
            keep.append(o)
        }
        hz.objects = keep
    }

    private mutating func landObject(_ o: FlyingObject, events: inout [SimEvent]) {
        var blocked: Int?
        if o.blockTime > 0 {
            for (i, p) in mission.rescuePoints.enumerated() where abs(o.x - p.x) <= p.width / 2 + o.radius {
                if !isBlocked(i) { blocked = i; events.append(.padBlocked(pointIndex: i)) }
                hz.blockedUntil[i] = max(hz.blockedUntil[i], time + o.blockTime)
            }
        }
        hz.nextID += 1
        hz.rubble.append(Rubble(id: hz.nextID, kind: o.kind, x: o.x, y: mission.surfaceHeight(at: o.x),
                                until: time + (o.blockTime > 0 ? o.blockTime : 8)))
        events.append(.impact(kind: o.kind, x: o.x, blockedPoint: blocked))
    }

    // MARK: Ground flows

    private mutating func stepFlows(dt: Double, alive: Bool, _ events: inout [SimEvent]) {
        for (fi, f) in mission.flowList.enumerated() {
            if time >= f.start - f.warn, !hz.flows[fi].warned {
                hz.flows[fi].warned = true
                events.append(.flowWarning(flowIndex: fi, pointIndex: nil))
            }
            guard time >= f.start else { continue }
            if !hz.flows[fi].started { hz.flows[fi].started = true; events.append(.flowStarted(flowIndex: fi)) }
            let run = abs(f.x1 - f.x0)
            let dir: Double = f.x1 >= f.x0 ? 1 : -1
            let travelled = min(run, f.speed * (time - f.start))
            hz.flows[fi].front = f.x0 + dir * travelled
            if let len = f.length {
                hz.flows[fi].tail = f.x0 + dir * min(run, max(0, f.speed * (time - f.start) - len))
            } else {
                hz.flows[fi].tail = f.x0
            }
            guard let span = hz.flows[fi].span else { continue }

            for (pi, p) in mission.rescuePoints.enumerated() {
                let left = p.x - p.width / 2, right = p.x + p.width / 2
                let ahead = dir > 0 ? left - span.hi : span.lo - right
                let waiting = people.indices.filter {
                    people[$0].pointIndex == pi && [.waiting, .boarding, .hoisting].contains(people[$0].state)
                }
                guard !waiting.isEmpty else { continue }
                if span.hi >= left && span.lo <= right {
                    for i in waiting {
                        people[i].state = .lost
                        events.append(.lost(personID: people[i].id, pointIndex: pi))
                    }
                } else if ahead > 0, ahead <= max(220, f.speed * 3), !hz.flowPointWarned.contains(fi * 1000 + pi) {
                    hz.flowPointWarned.insert(fi * 1000 + pi)
                    events.append(.flowWarning(flowIndex: fi, pointIndex: pi))
                }
            }

            if alive, heli.x >= span.lo - 25, heli.x <= span.hi + 25, mission.passageIndex(at: heli.x).map({ !mission.passageList[$0].isTunnel }) ?? true,
               heli.y - mission.surfaceHeight(at: heli.x) < f.clearance {
                heli.durability = max(0, heli.durability - f.damagePerSecond * dt)
                hz.flowHurtTimer -= dt
                if hz.flowHurtTimer <= 0 { hz.flowHurtTimer = 2.5; events.append(.flowScorched(flowIndex: fi)) }
            }
        }
    }

    // MARK: Winch

    mutating func stepWinch(dt: Double, _ events: inout [SimEvent]) {
        guard mission.rescuePoints.contains(where: \.isWinch) else { return }
        var active: WinchState?
        if !heli.onGround, heli.fuel > 0 {
            for (pi, p) in mission.rescuePoints.enumerated() where p.isWinch {
                let h = heli.y - p.top
                guard abs(heli.x - p.x) <= Self.winchTolerance, h >= Self.winchMinHeight, h <= p.cableLength else { continue }
                let candidate = people.firstIndex { $0.pointIndex == pi && $0.state == .hoisting }
                    ?? people.firstIndex { $0.pointIndex == pi && $0.state == .waiting }
                guard let ci = candidate else { continue }
                if people[ci].state == .waiting, aboardCount >= mission.capacity {
                    if !cabinFullSent { cabinFullSent = true; events.append(.cabinFull) }
                    continue
                }
                let steady = abs(heli.vx) <= Self.winchMaxSpeed && abs(heli.vy) <= Self.winchMaxSpeed + 10 && abs(heli.tilt) < 0.3
                active = WinchState(pointIndex: pi, personID: people[ci].id, progress: hz.winchProgress[pi], steady: steady, cable: h)
                break
            }
        }
        var holding = false
        for pi in hz.winchProgress.indices where mission.rescuePoints[pi].isWinch {
            if let a = active, a.pointIndex == pi {
                let i = people.firstIndex { $0.id == a.personID }!
                if a.steady {
                    holding = true
                    if people[i].state == .waiting { people[i].state = .hoisting; events.append(.winchStarted(pointIndex: pi)) }
                    hz.winchProgress[pi] = min(1, hz.winchProgress[pi] + dt / Self.winchTime)
                } else {
                    hz.winchProgress[pi] = max(0, hz.winchProgress[pi] - 0.5 * dt)
                }
                people[i].progress = hz.winchProgress[pi]
                if hz.winchProgress[pi] >= 1 {
                    people[i].state = .aboard
                    people[i].progress = 0
                    hz.winchProgress[pi] = 0
                    events.append(.boarded(personID: people[i].id))
                }
                if people[i].state == .hoisting, hz.winchProgress[pi] <= 0 { people[i].state = .waiting }
            } else if hz.winchProgress[pi] > 0 {
                hz.winchProgress[pi] = max(0, hz.winchProgress[pi] - 0.8 * dt)
                if let i = people.firstIndex(where: { $0.pointIndex == pi && $0.state == .hoisting }) {
                    people[i].progress = hz.winchProgress[pi]
                    if hz.winchProgress[pi] <= 0 { people[i].state = .waiting }
                }
            }
        }
        if hz.winchHolding, !holding { events.append(.winchSlipped) }
        hz.winchHolding = holding
        hz.winch = active
    }
}
