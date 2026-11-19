import Testing
@testable import RotorwachtCore

@Suite struct LandingTests {
    let mission = makeMission()
    let dt = 1.0 / 60

    /// Drops the helicopter with a given speed and returns the state after touchdown.
    private func touchdown(vy: Double, vx: Double = 0, tilt: Double = 0, x: Double = 1000, y: Double = 5,
                           waterLevel: Double = -100) -> (HelicopterState, [PhysicsEvent]) {
        var s = HelicopterState(x: x, y: y, fuel: 100)
        s.onGround = false
        s.vy = vy; s.vx = vx; s.tilt = tilt
        var ev: [PhysicsEvent] = []
        var spec = HelicopterSpec.standard
        spec.verticalResponse = 0 // keep the speed we set
        spec.drag = 0
        for _ in 0..<120 where !s.onGround {
            ev += HelicopterPhysics.step(&s, input: PilotInput(), dt: dt, wind: 0, waterLevel: waterLevel,
                                         mission: mission, fuelBurnPerSecond: 0, spec: spec)
        }
        return (s, ev)
    }

    @Test func softLandingCausesNoDamage() {
        let (s, ev) = touchdown(vy: -40)
        #expect(s.onGround)
        #expect(s.durability == 100)
        #expect(s.y == 0)
        #expect(ev.contains { if case .touchdown(_, let d) = $0 { return d == 0 } else { return false } })
    }

    @Test func hardLandingCausesDamage() {
        let (s, _) = touchdown(vy: -200)
        #expect(s.durability < 100)
        #expect(s.durability > 0)
    }

    @Test func damageGrowsWithSpeed() {
        let (a, _) = touchdown(vy: -140)
        let (b, _) = touchdown(vy: -250)
        #expect(b.durability < a.durability)
    }

    @Test func veryHardLandingDestroysTheHelicopter() {
        let (s, _) = touchdown(vy: -400)
        #expect(s.durability == 0)
    }

    @Test func sidewaysSpeedAndTiltHurt() {
        let (fast, _) = touchdown(vy: -30, vx: 200)
        #expect(fast.durability < 100)
        let (tilted, _) = touchdown(vy: -60, tilt: 0.42, y: 1)
        #expect(tilted.durability < 100)
    }

    @Test func landsOnRoofNotOnGround() {
        let (s, _) = touchdown(vy: -30, x: 500, y: 110)
        #expect(s.onGround)
        #expect(s.y == 100)
        #expect(s.durability == 100)
    }

    @Test func partlyOverEdgeStillRestsOnRoof() {
        // Footprint half width 42: at x = 500 + 80 + 30 a skid still touches the roof edge.
        let (s, _) = touchdown(vy: -30, x: 500 + 80 + 30, y: 110)
        #expect(s.y == 100)
    }

    @Test func ditchingInWaterIsSoftButWet() {
        var s = HelicopterState(x: 1000, y: 30, fuel: 100)
        s.onGround = false
        s.vy = -60
        var spec = HelicopterSpec.standard
        spec.verticalResponse = 0
        var ev: [PhysicsEvent] = []
        for _ in 0..<120 {
            ev += HelicopterPhysics.step(&s, input: PilotInput(), dt: dt, wind: 0, waterLevel: 20,
                                         mission: mission, fuelBurnPerSecond: 0, spec: spec)
        }
        #expect(s.inWater)
        #expect(s.y == 20)
        #expect(s.durability < 100, "drains while in the water")
        #expect(!ev.contains { if case .touchdown = $0 { return true } else { return false } })
    }
}
