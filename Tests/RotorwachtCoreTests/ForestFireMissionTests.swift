import Testing
@testable import RotorwachtCore

@Suite struct ForestFireMissionTests {
    @Test func missionTwoLoadsAndIsConsistent() throws {
        let m = try MissionLibrary.load("waldbrand")
        #expect(m.number == 2)
        #expect(m.isFire)
        #expect(m.totalPeople == 24)
        #expect(m.capacity == 12)
        #expect(m.helicopters == 3)
        #expect(m.fire != nil)
        #expect(m.lakeList.count == 2)
        // Every rescue point has its platform at or above the terrain under it.
        for p in m.rescuePoints {
            #expect(p.top >= m.maxSurface(from: p.x - p.width / 2, to: p.x + p.width / 2) - 1, "\(p.id)")
        }
        // Lakes: ground below the level inside, banks at the level at the edges, no fuel on the water.
        for l in m.lakeList {
            let mid = (l.x0 + l.x1) / 2
            #expect(m.groundHeight(at: mid) < l.level, "\(l.name)")
            #expect(abs(m.groundHeight(at: l.x0) - l.level) < 12, "\(l.name) west bank")
            #expect(abs(m.groundHeight(at: l.x1) - l.level) < 12, "\(l.name) east bank")
        }
        // The camp is dry, flat and outside the forest.
        #expect(m.waterLevel(from: m.base.x - 210, to: m.base.x + 210, flood: m.floodLevel(at: 0)) < m.baseSurface)
        let field = FireField(mission: m)
        let campCell = field.index(at: m.base.x)!
        #expect(field.cells[campCell].fuel == 0)
        for l in m.lakeList { #expect(field.cells[field.index(at: (l.x0 + l.x1) / 2)!].fuel == 0) }
        #expect(field.hasPendingIgnitions) // the fires break out on schedule
        #expect(m.fire!.ignitions.contains { $0.time > 0 })
    }

    @Test func allMissionsInTheMenuLoad() throws {
        for id in MissionLibrary.all { let m = try MissionLibrary.load(id); #expect(m.id == id) }
        #expect(MissionLibrary.all == ["hochwasser", "waldbrand", "kueste", "altstadt", "vulkan", "gebirge"])
    }

    @Test func existingMissionStillHasNoFire() throws {
        let m = try MissionLibrary.load("hochwasser")
        #expect(m.fire == nil)
        #expect(!m.isFire)
        #expect(MissionSimulation(mission: m).fire.burningCount == 0)
    }

    @Test func peopleLeftAloneAreHurtByTheFire() throws {
        let m = try MissionLibrary.load("waldbrand")
        var sim = MissionSimulation(mission: m)
        steps(&sim, seconds: 300, dt: 1.0 / 30)
        #expect(sim.injuredCount > 0)
        #expect(sim.fire.burningCount >= 0)
    }

    @Test func autopilotFlowsThroughTheForestFireMission() throws {
        let mission = try MissionLibrary.load("waldbrand")
        var sim = MissionSimulation(mission: mission)
        let pilot = AutoPilot()
        var t = 0.0
        while !sim.isFinished && t < mission.timeLimit + 5 {
            sim.step(input: pilot.input(for: sim), dt: 1.0 / 60)
            t += 1.0 / 60
        }
        let r = try #require(sim.result)
        print("AUTOPILOT waldbrand: outcome=\(r.outcome) rescued=\(r.rescued)/\(r.total) injured=\(r.injured) heliLost=\(r.helicoptersLost) time=\(Int(r.timeUsed)) extinguished=\(sim.fire.extinguishedCount)")
        #expect(r.rescued >= 14)
    }
}
