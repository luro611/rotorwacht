import Testing
@testable import RotorwachtCore

@Suite struct PhysicsTests {
    let mission = makeMission()
    let dt = 1.0 / 60

    @discardableResult
    private func fly(_ s: inout HelicopterState, _ input: PilotInput, seconds: Double, wind: Double = 0) -> [PhysicsEvent] {
        var all: [PhysicsEvent] = []
        var t = 0.0
        while t < seconds {
            all += HelicopterPhysics.step(&s, input: input, dt: dt, wind: wind, waterLevel: -100,
                                          mission: mission, fuelBurnPerSecond: 0.5)
            t += dt
        }
        return all
    }

    private func airborne(x: Double = 1000, y: Double = 300) -> HelicopterState {
        var s = HelicopterState(x: x, y: y, fuel: 100)
        s.onGround = false
        return s
    }

    @Test func staysOnGroundWithoutInput() {
        var s = HelicopterState(x: 1000, y: 0, fuel: 100)
        fly(&s, PilotInput(), seconds: 2)
        #expect(s.onGround)
        #expect(s.y == 0)
    }

    @Test func liftsOffAndClimbs() {
        var s = HelicopterState(x: 1000, y: 0, fuel: 100)
        let ev = fly(&s, PilotInput(up: true), seconds: 2)
        #expect(!s.onGround)
        #expect(s.y > 100)
        #expect(ev.contains(.liftoff))
    }

    @Test func hoversWithoutInput() {
        var s = airborne()
        fly(&s, PilotInput(), seconds: 3)
        #expect(near(s.y, 300, 1))
    }

    @Test func accelerationHasInertia() {
        var s = airborne()
        fly(&s, PilotInput(right: true), seconds: 0.3)
        #expect(s.vx > 20)
        #expect(s.vx < 150, "does not jump to top speed at once")
        let vAtRelease = s.vx
        fly(&s, PilotInput(), seconds: 0.5)
        #expect(s.vx > 0, "keeps drifting after the key is released")
        #expect(s.vx < vAtRelease)
    }

    @Test func speedIsLimited() {
        var s = airborne(x: 100)
        fly(&s, PilotInput(right: true), seconds: 6)
        #expect(s.vx <= HelicopterSpec.standard.maxHorizontalSpeed * 1.15 + 0.001)
        #expect(s.vx > 150)
    }

    @Test func tiltFollowsFlightDirection() {
        var s = airborne()
        fly(&s, PilotInput(right: true), seconds: 1.5)
        #expect(s.tilt > 0.1)
        var l = airborne()
        fly(&l, PilotInput(left: true), seconds: 1.5)
        #expect(l.tilt < -0.1)
    }

    @Test func turnsAroundWhenDirectionChanges() {
        var s = airborne()
        fly(&s, PilotInput(right: true), seconds: 1)
        #expect(s.facing == 1)
        fly(&s, PilotInput(left: true), seconds: 0.2)
        #expect(s.facing < 1)
        #expect(s.facing > -1, "turn takes time")
        fly(&s, PilotInput(left: true), seconds: 1)
        #expect(s.facing == -1)
    }

    @Test func facesViewerWhenStanding() {
        var s = airborne()
        fly(&s, PilotInput(), seconds: 1.5)
        #expect(s.facing == 0)
    }

    @Test func windPushesTheHelicopter() {
        var s = airborne()
        fly(&s, PilotInput(), seconds: 2, wind: 150)
        #expect(s.x > 1000)
        #expect(s.vx > 50)
    }

    @Test func fuelBurnsAndEngineQuitsWhenEmpty() {
        var s = airborne()
        s.fuel = 0.3
        let ev = fly(&s, PilotInput(), seconds: 2)
        #expect(s.fuel == 0)
        #expect(ev.contains(.outOfFuel))
        #expect(s.vy < -50, "falls without engine")
    }

    @Test func flyingBurnsMoreThanStanding() {
        var a = HelicopterState(x: 1000, y: 0, fuel: 100)
        fly(&a, PilotInput(), seconds: 10)
        var b = airborne(); b.fuel = 100
        fly(&b, PilotInput(right: true), seconds: 10)
        #expect(b.fuel < a.fuel)
    }

    @Test func stopsAtWall() {
        var m = makeMission()
        m.terrain = [TerrainPoint(x: 0, y: 0), TerrainPoint(x: 1200, y: 0), TerrainPoint(x: 1210, y: 400), TerrainPoint(x: 2000, y: 400)]
        var s = airborne(x: 1000, y: 100)
        var t = 0.0
        while t < 6 {
            HelicopterPhysics.step(&s, input: PilotInput(right: true), dt: dt, wind: 0, waterLevel: -100,
                                   mission: m, fuelBurnPerSecond: 0.1)
            t += dt
        }
        #expect(s.x < 1200, "cannot fly into the rock")
        #expect(s.durability < 100, "hitting the wall at speed hurts")
    }

    @Test func staysInsideMissionArea() {
        var s = airborne(x: 1900, y: 300)
        fly(&s, PilotInput(right: true), seconds: 10)
        #expect(s.x <= mission.world.width)
    }

    @Test func realMissionLoadsAndIsConsistent() throws {
        let m = try MissionLibrary.load("hochwasser")
        #expect(m.totalPeople == 28)
        #expect(m.capacity == 12)
        #expect(m.helicopters == 3)
        // Base is on dry high ground that the flood never reaches.
        #expect(m.baseSurface > m.flood.maxLevel)
        // Every rescue point has its platform at or above the terrain.
        for p in m.rescuePoints { #expect(p.top >= m.groundHeight(at: p.x) - 1, "\(p.id)") }
    }
}
