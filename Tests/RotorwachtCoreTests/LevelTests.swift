import Testing
import Foundation
@testable import RotorwachtCore

/// Five levels (0.9.0). Medium stays the data as written; files stored by 0.8 keep loading.
@Suite struct LevelTests {
    @Test func fiveLevelsFromBeginnerToPro() {
        #expect(Difficulty.allCases == [.beginner, .easy, .medium, .hard, .pro])
        #expect(Difficulty.allCases.map(\.label) == ["Anfänger", "Leicht", "Mittel", "Schwer", "Profi"])
        // The stored keys of the older levels must never change.
        #expect(Difficulty.easy.rawValue == "easy" && Difficulty.medium.rawValue == "medium" && Difficulty.hard.rawValue == "hard")
        #expect(Difficulty.beginner.shifted(by: -1) == .beginner && Difficulty.pro.shifted(by: 3) == .pro)
    }

    @Test func everyStepIsHarderThanTheOneBefore() throws {
        for id in MissionLibrary.all {
            let m = try MissionLibrary.load(id)
            #expect(m.scaled(for: .medium) == m)
            let all = Difficulty.allCases.map { m.scaled(for: $0) }
            for level in all { try level.validate() }
            for (a, b) in zip(all, all.dropFirst()) {
                #expect(a.helicopters > b.helicopters, "\(id)")
                #expect(a.timeLimit > b.timeLimit && a.fuel.burnPerSecond < b.fuel.burnPerSecond, "\(id)")
            }
        }
    }

    private func temp(_ name: String, _ text: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Literal files as written by version 0.8.
    @Test func progressOfThreeLevelsStillLoads() throws {
        let url = try temp("progress.json", #"{"records":{"hochwasser|easy":{"stars":2,"score":900},"kueste|hard":{"stars":3,"score":1500},"vulkan|medium":{"stars":1,"score":400}}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let p = PlayerProgress.load(from: url)
        #expect(p.best("hochwasser", .easy) == MissionRecord(stars: 2, score: 900))
        #expect(p.best("kueste", .hard)?.stars == 3 && p.best("vulkan", .medium)?.score == 400)
        #expect(p.best("hochwasser", .beginner) == nil && p.best("hochwasser", .pro) == nil)
        #expect(p.isUnlocked("waldbrand", order: MissionLibrary.all))
    }

    @Test func highScoresOfThreeLevelsStillLoad() throws {
        let url = try temp("highscores.json", #"{"lists":{"kueste|hard":[{"date":"2026-11-20T10:00:00Z","name":"Mira","score":1700,"stars":3}]}}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        let s = HighScores.load(from: url)
        #expect(s.list("kueste", .hard).map(\.name) == ["Mira"])
        #expect(s.list("kueste", .pro).isEmpty)
    }

    @Test func endlessListOfOlderVersionsStaysTheMediumList() throws {
        let url = try temp("endless.json", #"{"entries":[{"date":"2026-11-20T10:00:00Z","name":"Mira","score":3100,"stages":4}]}"#)
        defer { try? FileManager.default.removeItem(at: url) }
        var s = EndlessScores.load(from: url)
        #expect(s.list(.medium).map(\.name) == ["Mira"] && s.list(.pro).isEmpty)
        s.add(EndlessEntry(name: "Kai", stages: 2, score: 800, date: Date(timeIntervalSince1970: 1_800_000_000)), level: .pro)
        #expect(s.list(.pro).map(\.name) == ["Kai"] && s.entries.map(\.name) == ["Mira"])
        s.save(to: url)
        #expect(EndlessScores.load(from: url) == s)
    }

    @Test func endlessFollowsTheChosenLevel() throws {
        for stage in [1, 4, 9] {
            #expect(EndlessGenerator.level(stage: stage, chosen: .medium) == EndlessGenerator.level(stage: stage))
            #expect(EndlessGenerator.level(stage: stage, chosen: .beginner).rank <= EndlessGenerator.level(stage: stage).rank)
            #expect(EndlessGenerator.level(stage: stage, chosen: .pro).rank >= EndlessGenerator.level(stage: stage).rank)
        }
        #expect(EndlessGenerator.level(stage: 1, chosen: .pro) == .hard && EndlessGenerator.level(stage: 9, chosen: .beginner) == .easy)
        #expect(EndlessRun(seed: 1).helicopters == 5)
        #expect(Difficulty.allCases.map { EndlessRun(seed: 1, level: $0).helicopters } == [7, 6, 5, 4, 3])
        #expect(try EndlessRun(seed: 3, level: .pro).mission().helicopters == 3)
    }
}
