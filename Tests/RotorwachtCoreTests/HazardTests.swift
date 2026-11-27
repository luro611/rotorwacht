import Testing
import Foundation
@testable import RotorwachtCore

private func airborne(_ x: Double, _ y: Double, fuel: Double = 100) -> HelicopterState {
    var h = HelicopterState(x: x, y: y, fuel: fuel, durability: 100)
    h.onGround = false
    h.vy = 0
    return h
}

private func events(_ sim: inout MissionSimulation, seconds: Double, input: PilotInput = PilotInput()) -> [SimEvent] {
    var all: [SimEvent] = []
    var t = 0.0
    while t < seconds { all += sim.step(input: input, dt: 1.0 / 60); t += 1.0 / 60 }
    return all
}

// MARK: Lightning

@Suite struct LightningTests {
    private func stormMission() -> Mission {
        var m = makeMission(people: 1)
        m.storms = [StormCell(x0: 300, x1: 900, start: 5, interval: 100, warn: 2, radius: 120, damage: 20)]
        return m
    }

    @Test func strikeIsAnnouncedBeforeItHits() {
        var sim = MissionSimulation(mission: stormMission())
        let ev = events(&sim, seconds: 3.5)          // t = 3.5: announced at 3, hits at 5
        #expect(ev.contains { if case .strikeWarning = $0 { return true } else { return false } })
        #expect(!ev.contains { if case .lightning = $0 { return true } else { return false } })
        #expect(sim.hz.strikes.count == 1 && sim.hz.strikes[0].age == nil)
        let ev2 = events(&sim, seconds: 2)
        #expect(ev2.contains { if case .lightning = $0 { return true } else { return false } })
    }

    @Test func heliUnderTheBoltIsHurtOneOutsideIsNot() {
        var sim = MissionSimulation(mission: stormMission())
        sim.debugPlaceHelicopter(airborne(600, 300))
        _ = events(&sim, seconds: 3.0)
        let aimed = sim.hz.strikes[0].x
        // Fly out of the circle during the warning: no damage.
        var away = sim
        away.debugPlaceHelicopter(airborne(aimed + 400, 300))
        _ = events(&away, seconds: 3)
        #expect(away.heli.durability == 100)
        // Stay below the strike: hit.
        sim.debugPlaceHelicopter(airborne(aimed, 300))
        let ev = events(&sim, seconds: 3)
        #expect(sim.heli.durability <= 80.01)
        #expect(ev.contains { if case .lightning(_, let hit) = $0 { return hit } else { return false } })
    }

    @Test func strikesRepeatAtTheGivenInterval() {
        var m = stormMission()
        m.storms![0].interval = 4
        var sim = MissionSimulation(mission: m)
        let ev = events(&sim, seconds: 16)
        let n = ev.filter { if case .lightning = $0 { return true } else { return false } }.count
        #expect(n >= 3)
    }
}

// MARK: Falling objects, aftershocks, lava bombs

@Suite struct VolleyTests {
    private func debrisMission(blockTime: Double = 6) -> Mission {
        var m = makeMission(people: 2)
        m.volleys = [Volley(kind: "debris", start: 1, interval: 0, repeats: 1, count: 1, stagger: 0, x0: 500, x1: 500,
                            spawnY: 300, speedMin: 0, speedMax: 0, angleMin: 0, angleMax: 0, gravity: 600,
                            warn: 0.5, radius: 20, damage: 15, blockTime: blockTime)]
        return m
    }

    @Test func debrisFallsAndBlocksThePadForAWhile() {
        var sim = MissionSimulation(mission: debrisMission())
        var ev = events(&sim, seconds: 0.8)
        #expect(ev.contains { if case .tremor = $0 { return true } else { return false } })   // warning came first
        ev = events(&sim, seconds: 2.5)
        #expect(ev.contains { if case .padBlocked(0) = $0 { return true } else { return false } })
        #expect(sim.isBlocked(0))
        #expect(!sim.hz.rubble.isEmpty)
        _ = events(&sim, seconds: 7)
        #expect(!sim.isBlocked(0))
        #expect(sim.hz.rubble.isEmpty)
    }

    @Test func nobodyBoardsWhileThePadIsBlocked() {
        var sim = MissionSimulation(mission: debrisMission(blockTime: 8))
        _ = events(&sim, seconds: 3)
        #expect(sim.isBlocked(0))
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 100, fuel: 100, durability: 100))
        _ = events(&sim, seconds: 3)
        #expect(sim.aboardCount == 0)
        _ = events(&sim, seconds: 8)   // cleared, boarding starts
        #expect(sim.aboardCount > 0)
    }

    @Test func debrisHitsAHelicopterInItsWay() {
        var sim = MissionSimulation(mission: debrisMission())
        sim.debugPlaceHelicopter(airborne(500, 130))
        let ev = events(&sim, seconds: 2.5)
        #expect(ev.contains { if case .struckByObject(let k, _) = $0 { return k == "debris" } else { return false } })
        #expect(sim.heli.durability <= 85.01)
    }

    @Test func lavaBombFollowsItsAnnouncedBallisticPath() {
        var m = makeMission(people: 1)
        m.volleys = [Volley(kind: "lavaBomb", start: 0, interval: 0, repeats: 1, count: 1, stagger: 0, x0: 200, x1: 200,
                            spawnY: 50, speedMin: 300, speedMax: 300, angleMin: 60, angleMax: 60, gravity: 300,
                            warn: 0, radius: 15, damage: 10, blockTime: 0)]
        var sim = MissionSimulation(mission: m)
        _ = events(&sim, seconds: 0.05)
        let o = try! #require(sim.hz.objects.first)
        let path = ballisticPath(o, ground: { m.surfaceHeight(at: $0) }, dt: 0.02, maxSteps: 400)
        let predicted = path.last!.x
        let ev = events(&sim, seconds: 6)
        var landed = -1.0
        for e in ev { if case .impact(_, let x, _) = e { landed = x } }
        #expect(landed > 0)
        #expect(abs(landed - predicted) < 25)
        #expect(sim.hz.objects.isEmpty)
    }

    @Test func repeatedVolleysKeepComing() {
        var m = debrisMission(blockTime: 0)
        m.volleys![0].repeats = 3; m.volleys![0].interval = 4; m.volleys![0].count = 2; m.volleys![0].stagger = 0.3
        var sim = MissionSimulation(mission: m)
        let ev = events(&sim, seconds: 14)
        let n = ev.filter { if case .objectLaunched = $0 { return true } else { return false } }.count
        #expect(n == 6)
    }
}

// MARK: Lava and avalanches

@Suite struct FlowTests {
    private func flowMission(kind: String, length: Double?) -> Mission {
        var m = makeMission(people: 2)
        m.flows = [Flow(id: "f", kind: kind, start: 0, warn: 1, x0: 100, x1: 1000, speed: 100, length: length,
                        damagePerSecond: 30, clearance: 60)]
        return m
    }

    @Test func lavaWarnsThenTakesThePeopleAtThePoint() {
        var sim = MissionSimulation(mission: flowMission(kind: "lava", length: nil))
        let ev = events(&sim, seconds: 5)    // front 100 + 500; pad covers 420...580
        let warnAt = ev.firstIndex { if case .flowWarning(_, let p) = $0 { return p == 0 } else { return false } }
        let lostAt = ev.firstIndex { if case .lost = $0 { return true } else { return false } }
        #expect(warnAt != nil && lostAt != nil && warnAt! < lostAt!)
        #expect(sim.people.allSatisfy { $0.state == .lost })
    }

    @Test func peopleAlreadyAboardAreSafe() {
        var sim = MissionSimulation(mission: flowMission(kind: "lava", length: nil))
        for i in sim.people.indices { sim.people[i].state = .aboard }
        _ = events(&sim, seconds: 6)
        #expect(sim.people.allSatisfy { $0.state != .lost })
    }

    @Test func lavaStaysAvalancheGoesAway() {
        var lava = MissionSimulation(mission: flowMission(kind: "lava", length: nil))
        _ = events(&lava, seconds: 14)
        #expect(lava.hz.flows[0].span != nil)
        var snow = MissionSimulation(mission: flowMission(kind: "avalanche", length: 150))
        for i in snow.people.indices { snow.people[i].state = .aboard }   // keeps the mission running
        snow.debugPlaceHelicopter(airborne(1800, 600))                      // ...and away from the camp
        _ = events(&snow, seconds: 4)
        #expect(snow.hz.flows[0].span != nil)
        #expect(snow.hz.flows[0].span!.hi - snow.hz.flows[0].span!.lo <= 150.5)
        _ = events(&snow, seconds: 10)
        #expect(snow.hz.flows[0].span == nil)
    }

    @Test func lowFlyingHelicopterInsideTheBandIsHurtOneHighUpIsNot() {
        var low = MissionSimulation(mission: flowMission(kind: "lava", length: nil))
        _ = events(&low, seconds: 2)    // band reaches x = 300
        low.debugPlaceHelicopter(airborne(200, 20))
        _ = events(&low, seconds: 1)
        #expect(low.heli.durability < 80)
        var high = MissionSimulation(mission: flowMission(kind: "lava", length: nil))
        _ = events(&high, seconds: 2)
        high.debugPlaceHelicopter(airborne(200, 200))
        _ = events(&high, seconds: 1)
        #expect(high.heli.durability == 100)
    }

    @Test func flowOutsideItsRunDoesNotTouchOtherPoints() {
        var m = flowMission(kind: "avalanche", length: 100)
        m.flows![0].x1 = 300     // stops before the pad at 420
        var sim = MissionSimulation(mission: m)
        _ = events(&sim, seconds: 10)
        #expect(sim.people.allSatisfy { $0.state == .waiting })
    }
}

// MARK: Winch

@Suite struct WinchTests {
    private func winchMission() -> Mission {
        var m = makeMission(people: 2)
        m.rescuePoints = [RescuePointSpec(id: "w", name: "W", kind: "ledge", x: 500, width: 60, top: 100, people: 2,
                                          access: "winch", cable: 120)]
        return m
    }

    @Test func hoversSteadyAndPeopleComeUpOneByOne() {
        var sim = MissionSimulation(mission: winchMission())
        sim.debugPlaceHelicopter(airborne(500, 170))
        _ = events(&sim, seconds: 1)
        let w = try! #require(sim.hz.winch)
        #expect(w.steady && w.progress > 0)
        #expect(sim.people.contains { $0.state == .hoisting })
        _ = events(&sim, seconds: MissionSimulation.winchTime + 0.5)
        #expect(sim.people.filter { $0.state == .aboard }.count == 1)
        _ = events(&sim, seconds: MissionSimulation.winchTime + 0.3)
        #expect(sim.people.filter { $0.state == .aboard }.count == 2)
    }

    @Test func crashClearsTheCable() {
        var sim = MissionSimulation(mission: winchMission())
        sim.debugPlaceHelicopter(airborne(500, 170))
        _ = events(&sim, seconds: 1)
        #expect(sim.hz.winch != nil)
        sim.heli.durability = 0
        _ = events(&sim, seconds: 0.1)
        #expect(sim.hz.winch == nil && sim.hz.winchProgress.allSatisfy { $0 == 0 })
        #expect(!sim.people.contains { $0.state == .hoisting })
    }

    @Test func movingFastOrFlyingTooHighHoistsNobody() {
        var sim = MissionSimulation(mission: winchMission())
        sim.debugPlaceHelicopter(airborne(500, 300))      // cable is 120 long
        _ = events(&sim, seconds: 5)
        #expect(sim.hz.winch == nil && sim.aboardCount == 0)
        var moving = MissionSimulation(mission: winchMission())
        var h = airborne(430, 170); h.vx = 120
        moving.debugPlaceHelicopter(h)
        _ = events(&moving, seconds: 1.2, input: PilotInput(right: true))
        #expect(moving.aboardCount == 0)
    }

    @Test func shakingLosesProgressAndRaisesASlipEvent() {
        var sim = MissionSimulation(mission: winchMission())
        sim.debugPlaceHelicopter(airborne(500, 170))
        _ = events(&sim, seconds: 1.5)
        #expect((sim.hz.winch?.progress ?? 0) > 0.3)
        sim.debugPlaceHelicopter({ var h = airborne(500, 170); h.vx = 90; return h }())
        let ev = events(&sim, seconds: 0.3)
        #expect(ev.contains { $0 == .winchSlipped })
    }

    @Test func landingOnALedgeDoesNotBoardAnybody() {
        var sim = MissionSimulation(mission: winchMission())
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 100, fuel: 100, durability: 100))
        _ = events(&sim, seconds: 4)
        #expect(sim.aboardCount == 0)
    }

    @Test func fullCabinStopsTheCable() {
        var m = winchMission()
        m.capacity = 1
        var sim = MissionSimulation(mission: m)
        sim.debugPlaceHelicopter(airborne(500, 170))
        let ev = events(&sim, seconds: 2 * MissionSimulation.winchTime + 1)
        #expect(sim.people.filter { $0.state == .aboard }.count == 1)
        #expect(ev.contains { $0 == .cabinFull })
    }
}

// MARK: Outposts, swell, atmosphere

@Suite struct SupplyAndSeaTests {
    @Test func outpostRefuelsAndKeepsTheHelicopterFromBeingStranded() {
        var m = makeMission(people: 1)
        m.outposts = [Outpost(name: "O", x: 900, width: 120)]
        var sim = MissionSimulation(mission: m)
        sim.debugPlaceHelicopter(HelicopterState(x: 900, y: 0, fuel: 0, durability: 100))
        let ev = events(&sim, seconds: 6)
        #expect(sim.heli.fuel > 30)
        #expect(ev.contains { $0 == .refueling })
        #expect(sim.helicoptersLeft == 3)
        // The same helicopter on bare ground without fuel is written off.
        var bare = MissionSimulation(mission: m)
        bare.debugPlaceHelicopter(HelicopterState(x: 1200, y: 0, fuel: 0, durability: 100))
        _ = events(&bare, seconds: 6)
        #expect(bare.helicoptersLeft == 2)
    }

    @Test func swellMovesTheSeaWithinItsAmplitude() {
        var m = makeMission(flood: FloodSpec(startLevel: 20, risePerSecond: 0, maxLevel: 20, swell: SwellSpec(amplitude: 14, period: 6)))
        m.world.width = 2000
        var lo = Double.infinity, hi = -Double.infinity
        var t = 0.0
        while t < 60 { let l = m.floodLevel(at: t); lo = min(lo, l); hi = max(hi, l); t += 0.05 }
        #expect(lo >= 20 - 14 - 1e-9 && hi <= 20 + 14 + 1e-9)
        #expect(hi - lo > 14)
        #expect(m.highestWater == 34)
    }

    @Test func ashDensityFollowsBaseAndPulses() {
        var m = makeMission()
        #expect(m.ashDensity(at: 5) == 0)
        m.atmosphere = AtmosphereSpec(sky: "ash", precipitation: "ash",
                                      ash: AshSpec(base: 0.1, pulses: [GustSpec(start: 10, duration: 10, strength: 0.5)]))
        #expect(near(m.ashDensity(at: 0), 0.1, 1e-9))
        #expect(near(m.ashDensity(at: 15), 0.6, 1e-9))
        #expect(m.ashDensity(at: 30) < 0.11)
    }
}

// MARK: Difficulty and progress

@Suite struct DifficultyTests {
    @Test func mediumIsTheDataAsWrittenEasyAndHardScaleIt() throws {
        let m = try MissionLibrary.load("vulkan")
        #expect(m.scaled(for: .medium) == m)
        let easy = m.scaled(for: .easy), hard = m.scaled(for: .hard)
        #expect(easy.timeLimit > m.timeLimit && hard.timeLimit < m.timeLimit)
        #expect(easy.fuel.burnPerSecond < m.fuel.burnPerSecond && hard.fuel.burnPerSecond > m.fuel.burnPerSecond)
        #expect(easy.helicopters == 4 && hard.helicopters == 2)
        #expect(easy.flowList[0].speed < hard.flowList[0].speed)
        #expect(easy.volleyList[0].warn > hard.volleyList[0].warn)
        #expect(easy.volleyList[0].damage < hard.volleyList[0].damage)
        try easy.validate(); try hard.validate()
    }
}

@Suite struct PlayerProgressTests {
    private func result(stars: Int, score: Int = 100) -> MissionResult {
        MissionResult(outcome: .completed, total: 10, rescued: 10, lost: 0, injured: 0, timeUsed: 100,
                      helicoptersLost: 0, score: score, stars: stars)
    }
    private let order = MissionLibrary.all

    @Test func onlyTheFirstMissionIsOpenAtTheStart() {
        let p = PlayerProgress()
        #expect(p.isUnlocked(order[0], order: order))
        for id in order.dropFirst() { #expect(!p.isUnlocked(id, order: order)) }
    }

    @Test func clearingOneOpensTheNextOnly() {
        var p = PlayerProgress()
        p.record(missionID: order[0], level: .easy, result: result(stars: 1))
        #expect(p.isUnlocked(order[1], order: order))
        #expect(!p.isUnlocked(order[2], order: order))
        // No star, no progress.
        p.record(missionID: order[1], level: .medium, result: result(stars: 0))
        #expect(!p.isUnlocked(order[2], order: order))
        p.record(missionID: order[1], level: .hard, result: result(stars: 2))
        #expect(p.isUnlocked(order[2], order: order))
    }

    @Test func keepsTheBestPerMissionAndLevel() {
        var p = PlayerProgress()
        p.record(missionID: "a", level: .medium, result: result(stars: 2, score: 500))
        p.record(missionID: "a", level: .medium, result: result(stars: 1, score: 900))
        #expect(p.best("a", .medium) == MissionRecord(stars: 2, score: 900))
        #expect(p.best("a", .hard) == nil)
    }

    @Test func savesAndLoadsAndSurvivesAJunkFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotorwacht-test-\(UUID().uuidString)")
        let url = dir.appendingPathComponent("progress.json")
        var p = PlayerProgress()
        p.record(missionID: "kueste", level: .hard, result: result(stars: 3, score: 777))
        p.save(to: url)
        #expect(PlayerProgress.load(from: url) == p)
        try "not json".write(to: url, atomically: true, encoding: .utf8)
        #expect(PlayerProgress.load(from: url) == PlayerProgress())
        #expect(PlayerProgress.load(from: dir.appendingPathComponent("missing.json")) == PlayerProgress())
        try? FileManager.default.removeItem(at: dir)
    }
}

// MARK: The shipped missions

@Suite struct CampaignTests {
    @Test func allLoadInOrderAndAreValid() throws {
        #expect(MissionLibrary.all.count == 10)
        for (i, id) in MissionLibrary.all.enumerated() {
            let m = try MissionLibrary.load(id)
            #expect(m.id == id && m.number == i + 1)
            try m.validate()
            #expect(m.totalPeople > 0 && m.totalPeople >= m.capacity / 2)
            // The camp is flat enough to land on.
            let a = m.maxSurface(from: m.base.x - m.base.width / 2, to: m.base.x + m.base.width / 2)
            #expect(a - m.baseSurface < 3)
            for p in m.rescuePoints { #expect(p.top >= m.groundHeight(at: p.x) - 1) }
        }
    }

    @Test func eachNewMissionUsesItsBuildingBlocks() throws {
        let coast = try MissionLibrary.load("kueste")
        #expect(coast.isNight && !coast.stormList.isEmpty && coast.flood.swell != nil)
        #expect(coast.rescuePoints.allSatisfy { $0.top > coast.highestWater + 30 })   // the sea never reaches them
        let town = try MissionLibrary.load("altstadt")
        #expect(town.volleyList.contains { $0.kind == "debris" && $0.blockTime > 0 })
        let volcano = try MissionLibrary.load("vulkan")
        #expect(volcano.flowList.contains { $0.kind == "lava" } && volcano.volleyList.contains { $0.kind == "lavaBomb" })
        #expect(!volcano.outpostList.isEmpty && (volcano.atmosphere?.ash?.base ?? 0) > 0)
        let alps = try MissionLibrary.load("gebirge")
        #expect(alps.rescuePoints.filter(\.isWinch).count >= 3 && alps.flowList.allSatisfy { $0.kind == "avalanche" })
    }

    @Test func badHazardDataIsRejected() throws {
        var m = try MissionLibrary.load("kueste")
        m.storms![0].interval = 0
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        var v = try MissionLibrary.load("vulkan")
        v.volleys![0].kind = "meteor"
        #expect(throws: Mission.ValidationError.self) { try v.validate() }
        var g = try MissionLibrary.load("gebirge")
        g.flows![0].speed = 0
        #expect(throws: Mission.ValidationError.self) { try g.validate() }
    }

    /// Every Einsatz runs from the start to the result with the scripted pilot, on all three levels.
    @Test(arguments: MissionLibrary.all, Difficulty.allCases)
    func autopilotFlysEveryMissionToTheResult(id: String, level: Difficulty) throws {
        let mission = try MissionLibrary.load(id).scaled(for: level)
        var sim = MissionSimulation(mission: mission)
        let pilot = AutoPilot(fireFirst: id == "waldbrand")
        var t = 0.0
        while !sim.isFinished && t < mission.timeLimit + 10 {
            sim.step(input: pilot.input(for: sim), dt: 1.0 / 60)
            t += 1.0 / 60
        }
        let r = try #require(sim.result)
        #expect(r.outcome != .failed)
        #expect(Double(r.rescued) >= Double(r.total) * 0.6)
    }
}
