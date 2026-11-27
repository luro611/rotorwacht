import Testing
@testable import RotorwachtCore

@Suite struct PracticeTests {
    @Test(arguments: Practice.courses.map(\.id), Difficulty.allCases)
    func everyCourseIsValidAndStartsOnSolidGround(id: String, level: Difficulty) throws {
        let c = try #require(Practice.course(id))
        let base = try MissionLibrary.load(c.missionID)
        for slow in [false, true] {
            let m = base.practiced(course: c, level: level, slow: slow)
            try m.validate()
            #expect(m.isPractice && m.startX == c.startX)
            #expect(c.startX > 0 && c.startX < m.world.width)
            // Not inside a passage and not under water at the start.
            #expect(m.passageIndex(at: c.startX) == nil)
            #expect(m.surfaceHeight(at: c.startX) > m.floodLevel(at: 0) - 1 || m.flood.risePerSecond == 0)
            #expect(m.surfaceHeight(at: c.startX) > m.floodLevel(at: 0), "Start im Wasser: \(c.id)")
            let sim = MissionSimulation(mission: m)
            #expect(sim.heli.x == c.startX && sim.heli.y == m.surfaceHeight(at: c.startX))
        }
    }

    @Test func aLostHelicopterIsReplacedAtOnceAtTheCourseStart() throws {
        let c = try #require(Practice.course("tunnel"))
        let m = try MissionLibrary.load(c.missionID).practiced(course: c, level: .hard, slow: false)
        var sim = MissionSimulation(mission: m)
        for _ in 0..<5 {
            var h = sim.heli; h.durability = 0; h.x = 6200; sim.debugPlaceHelicopter(h)
            steps(&sim, seconds: 1.2)
            #expect(!sim.isFinished)
            #expect(sim.heli.x == c.startX && sim.heli.durability > 0)
        }
        #expect(sim.helicoptersLeft == m.helicopters)
        #expect(sim.heli.fuel == m.fuel.capacity)
    }

    @Test func slowedHazardsAreGentler() throws {
        let v = try MissionLibrary.load("vulkan"), g = try MissionLibrary.load("gebirge"), k = try MissionLibrary.load("kueste")
        let sv = v.slowed(), sg = g.slowed(), sk = k.slowed()
        #expect(sv.passages![0].shutters![0].open > v.passages![0].shutters![0].open)
        #expect(sv.passages![0].shutters![0].warn > v.passages![0].shutters![0].warn)
        #expect(sv.flows![0].speed < v.flows![0].speed && sg.flows![0].speed < g.flows![0].speed)
        #expect(sv.volleys![0].interval > v.volleys![0].interval)
        #expect(sk.storms![0].interval > k.storms![0].interval && sk.storms![0].damage < k.storms![0].damage)
        try sv.validate(); try sg.validate(); try sk.validate()
    }

    @Test func practiceNeverEndsInDefeat() throws {
        let c = try #require(Practice.course("blitze"))
        let m = try MissionLibrary.load(c.missionID).practiced(course: c, level: .hard, slow: false)
        var sim = MissionSimulation(mission: m)
        for _ in 0..<3 { var h = sim.heli; h.durability = 0; sim.debugPlaceHelicopter(h); steps(&sim, seconds: 1) }
        #expect(!sim.isFinished && sim.helicoptersLeft == 1)
    }

    @Test func normalMissionsAreUnchanged() throws {
        let m = try MissionLibrary.load("vulkan")
        #expect(!m.isPractice && m.startX == nil)
        let sim = MissionSimulation(mission: m)
        #expect(sim.heli.x == m.base.x)
    }
}
