import Testing
import Foundation
@testable import RotorwachtCore

@Suite struct EndlessTests {
    @Test func theSameSeedGivesTheSameEinsatz() throws {
        for stage in [1, 4, 9] {
            let a = try EndlessGenerator.mission(seed: 42, stage: stage, helicopters: 5)
            let b = try EndlessGenerator.mission(seed: 42, stage: stage, helicopters: 5)
            #expect(a == b)
        }
        let c = try EndlessGenerator.mission(seed: 43, stage: 4, helicopters: 5)
        #expect(c != (try EndlessGenerator.mission(seed: 42, stage: 4, helicopters: 5)))
    }

    @Test func theBasesRotateAndNeverRepeatBackToBack() {
        for seed in UInt64(1)...40 {
            let ids = (1...18).map { EndlessGenerator.baseID(seed: seed, stage: $0) }
            for round in 0..<3 { #expect(Set(ids[(round * 6)..<(round * 6 + 6)]) == Set(EndlessKit.bases)) }
            for (a, b) in zip(ids, ids.dropFirst()) { #expect(a != b) }
        }
    }

    @Test(arguments: Array(UInt64(1)...25))
    func everyGeneratedEinsatzIsValid(seed: UInt64) throws {
        for stage in [1, 2, 3, 5, 8, 12, 20, 40] {
            let m = try EndlessGenerator.mission(seed: seed, stage: stage, helicopters: 4)
            try m.validate()
            #expect(m.helicopters == 4 && m.totalPeople >= 2 && m.rescuePoints.allSatisfy { $0.people >= 1 && $0.people <= 6 })
            #expect(m.timeLimit >= 150)
            // Hazards from the sky never sit in a passage.
            for s in m.stormList { #expect(!m.passageList.contains { $0.x1 + 100 > s.x0 && $0.x0 - 100 < s.x1 } || EndlessKit.bases.contains(m.id)) }
        }
    }

    @Test func laterStagesBringMoreBlocksAndPressure() throws {
        var early = 0, late = 0
        for seed in UInt64(1)...30 {
            early += try EndlessGenerator.generate(seed: seed, stage: 1, helicopters: 5).blocks.count
            late += try EndlessGenerator.generate(seed: seed, stage: 12, helicopters: 5).blocks.count
        }
        #expect(late > early)
        #expect(EndlessGenerator.pressure(stage: 1) == 0 && EndlessGenerator.pressure(stage: 12) == 1 && EndlessGenerator.pressure(stage: 99) == 1)
        #expect(EndlessGenerator.level(stage: 1) == .easy && EndlessGenerator.level(stage: 4) == .medium && EndlessGenerator.level(stage: 6) == .hard)
    }

    @Test func everyBlockOfTheKitCanBeAppliedToItsFittingEinsaetze() throws {
        for b in EndlessKit.blocks {
            var applied = 0
            for id in EndlessKit.bases {
                var m = try MissionLibrary.load(id)
                guard b.fits(m) else { continue }
                var rng = SeededRandom(seed: 5)
                b.apply(&m, &rng, 1)
                try m.validate()
                applied += 1
            }
            #expect(applied > 0, "block \(b.id) fits no Einsatz")
        }
    }

    @Test func aRunKeepsTheStockOfHelicopters() throws {
        func result(_ o: MissionOutcome = .completed, stars: Int = 3, lost: Int = 0) -> MissionResult {
            MissionResult(outcome: o, total: 10, rescued: 10, lost: 0, injured: 0, timeUsed: 100, helicoptersLost: lost, score: 500, stars: stars)
        }
        var run = EndlessRun(seed: 1)
        #expect(run.stage == 1 && run.helicopters == EndlessRun.startHelicopters)
        #expect(try run.mission().helicopters == EndlessRun.startHelicopters)
        let n1 = run.finish(result(lost: 2))
        #expect(n1 == .next(bonusHelicopter: false))
        #expect(run.helicopters == EndlessRun.startHelicopters - 2 && run.stage == 2 && run.stagesCleared == 1)
        #expect(try run.mission().helicopters == run.helicopters)
        #expect(run.score == 500 + EndlessRun.stageBonusPerStage)
        let n2 = run.finish(result())
        #expect(n2 == .next(bonusHelicopter: false))
        // Third cleared stage: one helicopter joins.
        let n3 = run.finish(result())
        #expect(n3 == .next(bonusHelicopter: true))
        #expect(run.helicopters == EndlessRun.startHelicopters - 1)
        #expect(run.stagesCleared == 3 && run.stage == 4)
    }

    @Test func theStockNeverGrowsPastTheLimit() {
        var run = EndlessRun(seed: 1)
        for _ in 0..<30 { run.finish(MissionResult(outcome: .completed, total: 4, rescued: 4, lost: 0, injured: 0, timeUsed: 1, helicoptersLost: 0, score: 1, stars: 3)) }
        #expect(run.helicopters == EndlessRun.maxHelicopters && !run.isOver)
    }

    @Test func aRunEndsWithoutStarsWithoutHelicoptersOrOnFailure() {
        func end(_ r: MissionResult) -> EndlessRun { var run = EndlessRun(seed: 2); run.finish(r); return run }
        func res(_ o: MissionOutcome, stars: Int, lost: Int) -> MissionResult {
            MissionResult(outcome: o, total: 10, rescued: stars * 3, lost: 0, injured: 0, timeUsed: 1, helicoptersLost: lost, score: 80, stars: stars)
        }
        let noStars = end(res(.timeUp, stars: 0, lost: 0))
        #expect(noStars.isOver && noStars.stagesCleared == 0 && noStars.score == 80)
        #expect(end(res(.failed, stars: 1, lost: 5)).isOver)
        #expect(end(res(.completed, stars: 2, lost: EndlessRun.startHelicopters)).isOver)
        #expect(!end(res(.timeUp, stars: 1, lost: 0)).isOver)
        var over = noStars
        let again = over.finish(res(.completed, stars: 3, lost: 0))
        #expect(again == .over)
    }

    @Test func endlessScoresRankByStagesThenPoints() {
        var s = EndlessScores()
        let d = Date(timeIntervalSince1970: 1_800_000_000)
        s.add(EndlessEntry(name: "A", stages: 3, score: 2000, date: d))
        s.add(EndlessEntry(name: "B", stages: 5, score: 1500, date: d.addingTimeInterval(1)))
        s.add(EndlessEntry(name: "C", stages: 5, score: 1800, date: d.addingTimeInterval(2)))
        #expect(s.entries.map(\.name) == ["C", "B", "A"])
        let zero = s.add(EndlessEntry(name: "  ", stages: 0, score: 0, date: d))
        #expect(zero == nil)
        for i in 0..<12 { s.add(EndlessEntry(name: "P\(i)", stages: 1, score: 100 + i, date: d.addingTimeInterval(Double(10 + i)))) }
        #expect(s.entries.count == EndlessScores.limit)
        #expect(s.place(stages: 1, score: 50) == nil)
        let e = s.entries[0]
        let renamed = s.rename(place: 0, date: e.date, to: String(repeating: "x", count: 40))
        #expect(renamed)
        #expect(s.entries[0].name.count == HighScores.maxNameLength)
        let stale = s.rename(place: 0, date: d.addingTimeInterval(999), to: "no")
        #expect(!stale)
    }

    @Test func endlessScoresSurviveSavingAndBrokenFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("endless-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        var s = EndlessScores()
        s.add(EndlessEntry(name: "Mira", stages: 4, score: 3100, date: Date(timeIntervalSince1970: 1_800_000_000)))
        s.save(to: url)
        #expect(EndlessScores.load(from: url) == s)
        try Data("nope".utf8).write(to: url)
        #expect(EndlessScores.load(from: url) == EndlessScores())
    }

    /// The generator must always give a solvable Einsatz: the scripted pilot saves at least half of the people (one star,
    /// which is what a stage needs to go on) on every ground and stage, with the stock of helicopters not used up.
    @Test(arguments: EndlessKit.bases, [1, 4, 8, 13, 20])
    func autopilotSolvesGeneratedEinsaetze(base: String, stage: Int) throws {
        var failures: [String] = []
        for seed in UInt64(1)...6 {
            let m = try EndlessGenerator.mission(seed: seed &* 977 &+ UInt64(stage), stage: stage, helicopters: 3, base: base)
            var sim = MissionSimulation(mission: m)
            let pilot = AutoPilot(fireFirst: base == "waldbrand")
            var t = 0.0
            while !sim.isFinished && t < m.timeLimit + 10 { sim.step(input: pilot.input(for: sim), dt: 1.0 / 60); t += 1.0 / 60 }
            guard let r = sim.result else { failures.append("seed \(seed): no result"); continue }
            if r.outcome == .failed || Double(r.rescued) < Double(r.total) * 0.5 {
                failures.append("seed \(seed): \(r.outcome) \(r.rescued)/\(r.total) heliLost \(r.helicoptersLost)")
            }
        }
        #expect(failures.isEmpty, "\(base) stage \(stage): \(failures.joined(separator: "; "))")
    }
}
