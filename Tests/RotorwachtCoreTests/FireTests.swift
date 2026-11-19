import Testing
@testable import RotorwachtCore

/// A flat forest mission for exact fire tests: forest from x=200 to 1800, ground at 0.
func makeFireMission(ignitions: [IgnitionSpec] = [], burnTime: Double = 30, spreadRate: Double = 0.5,
                     lakes: [LakeSpec]? = nil, people: Int = 2) -> Mission {
    var m = makeMission(people: people)
    m.hazard = "fire"
    m.lakes = lakes
    m.fire = FireSpec(cellWidth: 40, burnTime: burnTime, spreadRate: spreadRate,
                      zones: [FuelZone(x0: 200, x1: 1800, fuel: 1)], ignitions: ignitions)
    return m
}

@Suite struct TankTests {
    private let lake = [LakeSpec(name: "See", x0: 300, x1: 900, level: 20)]

    private func lakeMission() -> Mission {
        var m = makeFireMission(lakes: lake)
        // dig the lake basin: ground below the level between 300 and 900
        m.terrain = [TerrainPoint(x: 0, y: 60), TerrainPoint(x: 280, y: 60), TerrainPoint(x: 320, y: -30),
                     TerrainPoint(x: 880, y: -30), TerrainPoint(x: 920, y: 60), TerrainPoint(x: 2000, y: 60)]
        m.rescuePoints = [RescuePointSpec(id: "a", name: "A", kind: "roof", x: 1400, width: 160, top: 150, people: 2)]
        m.base = BaseSpec(x: 1800, width: 300)
        return m
    }

    @Test func startsFullAndDropsEmptyTheTank() {
        var sim = MissionSimulation(mission: makeFireMission())
        #expect(sim.heli.water == 100)
        sim.debugPlaceHelicopter(HelicopterState(x: 800, y: 300, fuel: 100, durability: 100).with(water: 100, airborne: true))
        steps(&sim, PilotInput(drop: true), seconds: 3)
        // 16 droplets per second for 3 seconds
        #expect(near(sim.heli.water, 100 - 48, 3))
        steps(&sim, PilotInput(drop: true), seconds: 10)
        #expect(sim.heli.water < 1)
    }

    @Test func noDropWhenEmptyOrOnTheGround() {
        var sim = MissionSimulation(mission: makeFireMission())
        steps(&sim, PilotInput(drop: true), seconds: 2)   // still standing on the pad
        #expect(sim.heli.water == 100)
        #expect(sim.drops.isEmpty)
    }

    @Test func skimmingOverALakeFillsTheTank() {
        var sim = MissionSimulation(mission: lakeMission())
        var h = HelicopterState(x: 600, y: 45, fuel: 100, durability: 100).with(water: 10, airborne: true)
        h.vy = 0
        sim.debugPlaceHelicopter(h)
        steps(&sim, PilotInput(), seconds: 1)
        #expect(sim.filling)
        #expect(sim.heli.water > 35)
        steps(&sim, PilotInput(), seconds: 5)
        #expect(near(sim.heli.water, 100, 0.01))
    }

    @Test func noFillingHighAboveTheLakeOrOverLand() {
        var sim = MissionSimulation(mission: lakeMission())
        sim.debugPlaceHelicopter(HelicopterState(x: 600, y: 200, fuel: 100, durability: 100).with(water: 10, airborne: true))
        steps(&sim, PilotInput(), seconds: 0.5)
        #expect(!sim.filling)
        sim.debugPlaceHelicopter(HelicopterState(x: 1200, y: 90, fuel: 100, durability: 100).with(water: 10, airborne: true))
        steps(&sim, PilotInput(), seconds: 0.5)
        #expect(!sim.filling)
        #expect(sim.heli.water < 11)
    }

    @Test func dropletsKeepTheHelicopterSpeedAndFall() {
        var sim = MissionSimulation(mission: makeFireMission())
        var h = HelicopterState(x: 600, y: 400, fuel: 100, durability: 100).with(water: 100, airborne: true)
        h.vx = 200
        sim.debugPlaceHelicopter(h)
        sim.step(input: PilotInput(drop: true), dt: 1.0 / 60)
        steps(&sim, PilotInput(drop: true), seconds: 0.5)
        let d = sim.drops.first!
        #expect(d.vx > 100)          // inertia: flies on forward
        #expect(d.y < 400)           // and falls
        steps(&sim, PilotInput(), seconds: 4)
        #expect(sim.drops.isEmpty)   // all landed
    }

    @Test func refillsInTheCamp() {
        var sim = MissionSimulation(mission: makeFireMission())
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: 100).with(water: 0, airborne: false))
        steps(&sim, seconds: 3)
        #expect(sim.heli.water > 50)
    }
}

extension HelicopterState {
    func with(water: Double, airborne: Bool) -> HelicopterState {
        var s = self
        s.water = water
        s.onGround = !airborne
        return s
    }
}

@Suite struct FireTests {
    private func fireSim(_ m: Mission) -> MissionSimulation { MissionSimulation(mission: m) }

    @Test func startsAndOnlyBurnsWhereThereIsFuel() {
        var m = makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 0.5)])
        m.fire!.ignitions.append(IgnitionSpec(time: 0, x: 100, intensity: 0.5)) // outside the forest
        let sim = fireSim(m)
        #expect(sim.fire.burningCount == 1)
        #expect(sim.fire.cells[sim.fire.index(at: 100)!].burning == false)
    }

    @Test func spreadsToNeighbours() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 0.8)], burnTime: 60))
        steps(&sim, seconds: 3)
        #expect(sim.fire.burningCount > 1)
        steps(&sim, seconds: 20)
        let burningNow = sim.fire.cells.indices.filter { sim.fire.cells[$0].burning }
        let spread = sim.fire.center(of: burningNow.max()!) - sim.fire.center(of: burningNow.min()!)
        #expect(spread > 200)
    }

    @Test func burnsOutAndLeavesAsh() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 1)], burnTime: 5, spreadRate: 0.0))
        steps(&sim, seconds: 8)
        let c = sim.fire.cells[sim.fire.index(at: 1000)!]
        #expect(!c.burning)
        #expect(c.fuel == 0)
        #expect(c.charred)
        #expect(sim.fire.burningCount == 0)
    }

    @Test func spreadsFasterUphillThanDownhill() {
        func front(uphillToRight: Bool) -> Double {
            var m = makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 0.8)], burnTime: 60)
            m.terrain = uphillToRight
                ? [TerrainPoint(x: 0, y: 0), TerrainPoint(x: 2000, y: 600)]
                : [TerrainPoint(x: 0, y: 600), TerrainPoint(x: 2000, y: 0)]
            var sim = fireSim(m)
            steps(&sim, seconds: 12)
            let burning = sim.fire.cells.indices.filter { sim.fire.cells[$0].burning }
            return sim.fire.center(of: burning.max()!) - 1000
        }
        // Rightwards is uphill in the first case, downhill in the second.
        #expect(front(uphillToRight: true) > front(uphillToRight: false))
    }

    @Test func windPushesTheFlames() {
        func rightReach(wind: Double) -> Double {
            var m = makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 0.8)], burnTime: 60)
            m.wind = WindSpec(base: wind, gusts: [])
            var sim = fireSim(m)
            steps(&sim, seconds: 12)
            let burning = sim.fire.cells.indices.filter { sim.fire.cells[$0].burning }
            return sim.fire.center(of: burning.max()!) - 1000
        }
        #expect(rightReach(wind: 150) > rightReach(wind: -150))
    }

    @Test func scheduledIgnitionBreaksOutOnTime() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 5, x: 1000, intensity: 0.5)]))
        #expect(sim.fire.burningCount == 0)
        steps(&sim, seconds: 4)
        #expect(sim.fire.burningCount == 0)
        var events: [SimEvent] = []
        for _ in 0..<120 { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.fire.burningCount >= 1)
        #expect(events.contains(.fireStarted(x: 1000)))
    }

    @Test func waterPutsOutAFire() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 1)], burnTime: 100, spreadRate: 0))
        steps(&sim, seconds: 2)
        #expect(sim.fire.burningCount == 1)
        // Hover above the fire and drop.
        sim.debugPlaceHelicopter(HelicopterState(x: 1000, y: 150, fuel: 100, durability: 100).with(water: 100, airborne: true))
        steps(&sim, PilotInput(drop: true), seconds: 4)
        steps(&sim, seconds: 3)
        #expect(sim.fire.burningCount == 0)
        #expect(sim.fire.extinguishedCount >= 1)
        #expect(sim.fire.cells[sim.fire.index(at: 1000)!].fuel > 0.5)   // saved, not burnt out
    }

    @Test func wetGroundHoldsTheFlamesBack() {
        func burntRight(wet: Bool) -> Double {
            var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 1)], burnTime: 60, spreadRate: 0.6))
            if wet {
                // Soak a strip right of the fire.
                sim.debugPlaceHelicopter(HelicopterState(x: 1190, y: 120, fuel: 100, durability: 100).with(water: 100, airborne: true))
                steps(&sim, PilotInput(drop: true), seconds: 5)
            }
            sim.debugPlaceHelicopter(HelicopterState(x: 100, y: 800, fuel: 100, durability: 100).with(water: 0, airborne: true))
            steps(&sim, seconds: 12)
            return sim.fire.cells.indices.filter { sim.fire.center(of: $0) > 1250 && sim.fire.cells[$0].charred }.count > 0 ? 1 : 0
        }
        #expect(burntRight(wet: false) == 1)
        #expect(burntRight(wet: true) == 0)
    }

    @Test func peopleNearFlamesAreWarnedAndThenHurt() {
        var m = makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 500, intensity: 1)], burnTime: 100, spreadRate: 0, people: 2)
        m.fire!.zones = [FuelZone(x0: 300, x1: 700, fuel: 1)]
        var sim = fireSim(m)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 20) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(events.contains(.fireWarning(pointIndex: 0)))
        #expect(sim.injuredCount == 2)
        #expect(events.filter { if case .hurtByFire = $0 { true } else { false } }.count == 2)
    }

    @Test func extinguishingInTimeSavesThePeople() {
        var m = makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 500, intensity: 1)], burnTime: 100, spreadRate: 0, people: 2)
        m.fire!.zones = [FuelZone(x0: 300, x1: 700, fuel: 1)]
        var sim = fireSim(m)
        steps(&sim, seconds: 2)
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 150, fuel: 100, durability: 100).with(water: 100, airborne: true))
        steps(&sim, PilotInput(drop: true), seconds: 3)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: 100).with(water: 100, airborne: false))
        steps(&sim, seconds: 15)
        #expect(sim.fire.burningCount == 0)
        #expect(sim.injuredCount == 0)
    }

    @Test func heatHurtsAHelicopterInTheFlames() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 1)], burnTime: 100, spreadRate: 0))
        steps(&sim, seconds: 2)
        sim.debugPlaceHelicopter(HelicopterState(x: 1000, y: 40, fuel: 100, durability: 100).with(water: 0, airborne: true))
        steps(&sim, seconds: 2)
        #expect(sim.heat > 0.1)
        #expect(sim.heli.durability < 95)
        // far away: unharmed
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 40, fuel: 100, durability: 100).with(water: 0, airborne: true))
        steps(&sim, seconds: 1)
        #expect(sim.heli.durability > 99)
    }

    @Test func smokeThickensNearFlames() {
        var sim = fireSim(makeFireMission(ignitions: [IgnitionSpec(time: 0, x: 1000, intensity: 1)], burnTime: 100, spreadRate: 0))
        steps(&sim, seconds: 4)
        let near = sim.fire.smoke(atX: 1000, y: 100)
        let far = sim.fire.smoke(atX: 1600, y: 100)
        let high = sim.fire.smoke(atX: 1000, y: 700)
        #expect(near > far)
        #expect(near > high)
    }
}
