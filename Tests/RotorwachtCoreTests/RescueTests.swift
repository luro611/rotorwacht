import Testing
@testable import RotorwachtCore

@Suite struct RescueTests {
    /// A helicopter that cannot slow its fall, to provoke crashes.
    private var noBrake: HelicopterSpec { var s = HelicopterSpec.standard; s.verticalResponse = 0; return s }

    /// Puts the helicopter landed on the rooftop, as if the pilot had set down there.
    private func simLandedOnRoof(people: Int = 3, capacity: Int = 12) -> MissionSimulation {
        var sim = MissionSimulation(mission: makeMission(people: people, capacity: capacity))
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 100, fuel: 100))
        return sim
    }

    @Test func peopleBoardOneByOne() {
        var sim = simLandedOnRoof(people: 3)
        steps(&sim, seconds: 0.7)
        #expect(sim.aboardCount == 1, "first one is walking")
        steps(&sim, seconds: 3.5)
        #expect(sim.people.filter { $0.state == .aboard }.count == 3)
    }

    @Test func boardingEmitsEvents() {
        var sim = simLandedOnRoof(people: 1)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 3) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(events.contains { if case .boarded = $0 { return true } else { return false } })
    }

    @Test func capacityIsRespected() {
        var sim = simLandedOnRoof(people: 5, capacity: 2)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 8) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.aboardCount == 2)
        #expect(sim.people.filter { $0.state == .waiting }.count == 3)
        #expect(events.contains(.cabinFull))
    }

    @Test func noBoardingWhileHovering() {
        var sim = MissionSimulation(mission: makeMission(people: 3))
        var h = HelicopterState(x: 500, y: 140, fuel: 100)
        h.onGround = false
        sim.debugPlaceHelicopter(h)
        steps(&sim, seconds: 3)
        #expect(sim.aboardCount == 0)
    }

    @Test func liftOffInterruptsBoarding() {
        var sim = simLandedOnRoof(people: 3)
        steps(&sim, seconds: 0.7)
        #expect(sim.people.filter { $0.state == .boarding }.count == 1)
        steps(&sim, PilotInput(up: true), seconds: 0.5)
        #expect(sim.people.filter { $0.state == .boarding }.count == 0)
        #expect(sim.people.filter { $0.state == .waiting }.count == 3)
    }

    @Test func disembarkingAtBaseRescuesAndRefuels() {
        var sim = MissionSimulation(mission: makeMission(people: 2))
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 20, durability: 60))
        sim.debugSetPeople(aboard: 2)
        steps(&sim, seconds: 5)
        #expect(sim.rescuedCount == 2)
        #expect(sim.aboardCount == 0)
        #expect(near(sim.heli.fuel, 100, 0.001))
        #expect(sim.heli.durability > 60)
    }

    @Test func noDisembarkingOutsideBase() {
        var sim = simLandedOnRoof(people: 0)
        sim.debugSetPeople(aboard: 2)
        steps(&sim, seconds: 4)
        #expect(sim.rescuedCount == 0)
        #expect(sim.aboardCount == 2)
    }

    @Test func floodTakesPeopleOnLowRoofs() {
        let flood = FloodSpec(startLevel: 50, risePerSecond: 10, maxLevel: 500)
        var sim = MissionSimulation(mission: makeMission(flood: flood, people: 2))
        var events: [SimEvent] = []
        for _ in 0..<(60 * 4) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.lostCount == 0, "level 90 is below the roof at 100")
        #expect(events.contains(.floodWarning(pointIndex: 0)))
        for _ in 0..<(60 * 4) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.lostCount == 2)
    }

    @Test func crashLosesHelicopterAndInjuresPassengers() {
        var sim = MissionSimulation(mission: makeMission(people: 1), spec: noBrake)
        var h = HelicopterState(x: 1000, y: 300, fuel: 100)
        h.onGround = false
        h.vy = -600
        sim.debugPlaceHelicopter(h)
        sim.debugSetPeople(aboard: 3)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 4) { events += sim.step(input: PilotInput(down: true), dt: 1.0 / 60) }
        #expect(events.contains(.helicopterLost(remaining: 2)))
        #expect(sim.injuredCount == 3)
        #expect(sim.helicoptersLeft == 2)
        #expect(events.contains(.respawned), "replacement arrives at the base")
        #expect(sim.heli.x == 1500)
    }

    @Test func missionFailsWhenLastHelicopterIsLost() {
        var sim = MissionSimulation(mission: makeMission(people: 2, helicopters: 1), spec: noBrake)
        var h = HelicopterState(x: 1000, y: 300, fuel: 100)
        h.onGround = false; h.vy = -600
        sim.debugPlaceHelicopter(h)
        steps(&sim, PilotInput(down: true), seconds: 4)
        #expect(sim.result?.outcome == .failed)
    }

    @Test func missionCompletesWhenEveryoneIsResolved() {
        var sim = MissionSimulation(mission: makeMission(people: 1))
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 100, fuel: 100))
        steps(&sim, seconds: 2) // boards
        #expect(sim.aboardCount == 1)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100)) // teleport to the base
        steps(&sim, seconds: 6)
        let r = sim.result
        #expect(r?.outcome == .completed)
        #expect(r?.rescued == 1)
        #expect(r?.stars == 3)
    }

    @Test func timeUpEndsTheMission() {
        var sim = MissionSimulation(mission: makeMission(people: 2, timeLimit: 5))
        steps(&sim, seconds: 6)
        #expect(sim.result?.outcome == .timeUp)
        #expect(sim.result?.rescued == 0)
        #expect(sim.result?.stars == 0)
    }
}

@Suite struct FullMissionTests {
    /// The shipped mission must be winnable by a simple pilot; keeps tuning honest.
    @Test func autopilotRescuesMostPeopleInTheRealMission() throws {
        let mission = try MissionLibrary.load("hochwasser")
        var sim = MissionSimulation(mission: mission)
        let pilot = AutoPilot()
        var t = 0.0
        while !sim.isFinished && t < mission.timeLimit + 5 {
            sim.step(input: pilot.input(for: sim), dt: 1.0 / 60)
            t += 1.0 / 60
        }
        let r = try #require(sim.result)
        print("AUTOPILOT: outcome=\(r.outcome) rescued=\(r.rescued)/\(r.total) lost=\(r.lost) injured=\(r.injured) heliLost=\(r.helicoptersLost) time=\(Int(r.timeUsed))")
        #expect(r.rescued >= 20)
    }
}
