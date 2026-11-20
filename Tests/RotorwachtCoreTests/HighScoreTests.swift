import Testing
import Foundation
@testable import RotorwachtCore

@Suite struct HighScoreTests {
    private func e(_ name: String, _ score: Int, stars: Int = 1, day: Double = 0) -> ScoreEntry {
        ScoreEntry(name: name, score: score, stars: stars, date: Date(timeIntervalSince1970: 1_000_000 + day * 86_400))
    }

    @Test func sortsBestFirstAndReturnsThePlace() {
        var s = HighScores()
        #expect(s.add(e("A", 300), mission: "m", level: .medium) == 0)
        #expect(s.add(e("B", 500), mission: "m", level: .medium) == 0)
        #expect(s.add(e("C", 400), mission: "m", level: .medium) == 1)
        #expect(s.list("m", .medium).map(\.name) == ["B", "C", "A"])
    }

    @Test func equalScoresRankByStarsThenByAge() {
        var s = HighScores()
        s.add(e("alt", 400, stars: 2, day: 0), mission: "m", level: .easy)
        s.add(e("neu", 400, stars: 2, day: 5), mission: "m", level: .easy)
        s.add(e("sterne", 400, stars: 3, day: 9), mission: "m", level: .easy)
        #expect(s.list("m", .easy).map(\.name) == ["sterne", "alt", "neu"])
    }

    @Test func keepsOnlyTheTenBest() {
        var s = HighScores()
        for i in 1...10 { s.add(e("p\(i)", i * 100), mission: "m", level: .hard) }
        #expect(s.list("m", .hard).count == 10)
        // Too weak: not taken.
        #expect(s.add(e("zu schwach", 50), mission: "m", level: .hard) == nil)
        #expect(s.place(forScore: 50, stars: 0, mission: "m", level: .hard) == nil)
        // Equal to the tenth: comes after it, so it does not make the list.
        #expect(s.add(e("gleich", 100, day: 3), mission: "m", level: .hard) == nil)
        #expect(s.add(e("neu", 550), mission: "m", level: .hard) == 5)
        #expect(s.list("m", .hard).count == 10 && s.list("m", .hard).last?.name == "p2")
        #expect(s.list("m", .hard).first?.name == "p10")
    }

    @Test func zeroPointsNeverQualify() {
        var s = HighScores()
        #expect(s.add(e("Null", 0, stars: 0), mission: "m", level: .easy) == nil)
        #expect(s.list("m", .easy).isEmpty)
    }

    @Test func listsAreSeparatePerEinsatzAndLevel() {
        var s = HighScores()
        s.add(e("A", 100), mission: "m1", level: .easy)
        s.add(e("B", 200), mission: "m1", level: .hard)
        s.add(e("C", 300), mission: "m2", level: .easy)
        #expect(s.list("m1", .easy).map(\.name) == ["A"])
        #expect(s.list("m1", .hard).map(\.name) == ["B"])
        #expect(s.list("m2", .easy).map(\.name) == ["C"])
        #expect(s.list("m2", .medium).isEmpty)
    }

    @Test func namesAreCleaned() {
        #expect(HighScores.cleanName("  Lutz  ") == "Lutz")
        #expect(HighScores.cleanName("") == "Pilot")
        #expect(HighScores.cleanName("   \n ") == "Pilot")
        #expect(HighScores.cleanName("Zeile\nzwei") == "Zeile zwei")
        #expect(HighScores.cleanName("12345678901234567890").count == 16)
        var s = HighScores()
        s.add(e("   ", 100), mission: "m", level: .easy)
        #expect(s.list("m", .easy)[0].name == "Pilot")
    }

    @Test func storageRoundTripAndBadFiles() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rotorwacht-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("highscores.json")
        #expect(HighScores.load(from: url) == HighScores())            // missing file
        var s = HighScores()
        s.add(e("Lutz", 480, stars: 3, day: 2), mission: "gebirge", level: .hard)
        s.save(to: url)
        #expect(HighScores.load(from: url) == s)
        try Data("kaputt".utf8).write(to: url)
        #expect(HighScores.load(from: url) == HighScores())            // damaged file
    }
}
