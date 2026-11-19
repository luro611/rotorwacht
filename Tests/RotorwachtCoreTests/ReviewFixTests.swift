import Testing
@testable import RotorwachtCore

@Suite struct ReviewFixTests {
    @Test func emptyTankOnFirmGroundOutsideTheCampWritesTheHelicopterOff() {
        var sim = MissionSimulation(mission: makeMission(people: 1, helicopters: 2))
        var h = HelicopterState(x: 900, y: 0, fuel: 0, durability: 100)   // bare ground, away from the camp
        h.onGround = true
        sim.debugPlaceHelicopter(h)
        steps(&sim, seconds: 1.5)
        #expect(sim.helicoptersLeft == 2)
        steps(&sim, seconds: 2)
        #expect(sim.helicoptersLeft == 1)
        steps(&sim, seconds: 4)   // replacement arrives, fuelled, in the camp
        #expect(sim.heli.fuel > 0)
        #expect(abs(sim.heli.x - sim.mission.base.x) < 1)
    }

    @Test func emptyTankInTheCampIsNotWrittenOff() {
        var sim = MissionSimulation(mission: makeMission(helicopters: 2))
        var h = HelicopterState(x: 1500, y: 0, fuel: 0, durability: 100)
        h.onGround = true
        sim.debugPlaceHelicopter(h)
        steps(&sim, seconds: 6)
        #expect(sim.helicoptersLeft == 2)
        #expect(sim.heli.fuel > 20)   // refuelled
    }

    @Test func rooftopCountsWhereTheSkidsStand() {
        var sim = MissionSimulation(mission: makeMission())
        var h = HelicopterState(x: 500 + 80 + 35, y: 100, fuel: 100, durability: 100)  // 115 from centre, still on the roof
        h.onGround = true
        sim.debugPlaceHelicopter(h)
        steps(&sim, seconds: 0.1)
        #expect(sim.rescuePointUnderHelicopter() == 0)
    }

    @Test func validationRejectsBrokenMissions() throws {
        func broken(_ change: (inout Mission) -> Void) -> Mission { var m = makeMission(); change(&m); return m }
        try makeMission().validate()
        #expect(throws: Mission.ValidationError.self) { try broken { $0.wind.gusts = [GustSpec(start: 1, duration: 0, strength: 10)] }.validate() }
        #expect(throws: Mission.ValidationError.self) { try broken { $0.terrain = [TerrainPoint(x: 0, y: 0), TerrainPoint(x: 0, y: 5)] }.validate() }
        #expect(throws: Mission.ValidationError.self) { try broken { $0.capacity = 0 }.validate() }
        #expect(throws: Mission.ValidationError.self) { try broken { $0.base = BaseSpec(x: 5000, width: 100) }.validate() }
    }

    @Test func realMissionsPassValidation() throws {
        for id in MissionLibrary.all { try MissionLibrary.load(id).validate() }
    }

    @Test func flightIsIndependentOfStepSize() {
        func fly(dt: Double) -> HelicopterState {
            var s = HelicopterState(x: 1000, y: 0, fuel: 100, durability: 100)
            let m = makeMission()
            var t = 0.0
            while t < 6 {
                let input = t < 4 ? PilotInput(right: true, up: true) : PilotInput(left: true)
                HelicopterPhysics.step(&s, input: input, dt: dt, wind: 20, waterLevel: -100, mission: m, fuelBurnPerSecond: 0.5)
                t += dt
            }
            return s
        }
        let a = fly(dt: 1.0 / 60), b = fly(dt: 1.0 / 120)
        #expect(abs(a.x - b.x) < 20)
        #expect(abs(a.y - b.y) < 10)
        #expect(abs(a.vx - b.vx) < 5)
    }
}
