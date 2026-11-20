import Testing
@testable import RotorwachtCore

@Suite struct ScoringTests {
    /// Helicopter standing in the camp with `n` people aboard (`debugSetPeople`), run until all have stepped out.
    private func deliver(_ n: Int, others: Int = 0, capacity: Int = 12, time: Double = 600) -> (MissionSimulation, [SimEvent]) {
        var m = makeMission(people: others, capacity: capacity, timeLimit: time)
        if others == 0 { m.rescuePoints = [] }
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: n)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability))
        var events: [SimEvent] = []
        var t = 0.0
        while t < Double(n) * 1.6 + 3 { events += sim.step(input: PilotInput(), dt: 1.0 / 60); t += 1.0 / 60 }
        return (sim, events)
    }

    @Test func eachRescueGetsTimeAndComboBonus() {
        let (sim, events) = deliver(4)
        let scored = events.compactMap { e -> (Int, Int)? in if case .scored(let p, let c) = e { return (p, c) } else { return nil } }
        #expect(scored.map(\.1) == [1, 2, 3, 4])
        // Almost the whole time is left: close to the full time bonus; the chain adds 5 per earlier person.
        #expect(scored[0].0 >= 100 + Scoring.timeBonusMax - 1)
        #expect(scored[3].0 - scored[0].0 == 3 * Scoring.comboStep)
        #expect(sim.tally.combo == 4 && sim.tally.bestCombo == 4)
        #expect(sim.tally.comboBonus == (0 + 1 + 2 + 3) * Scoring.comboStep)
    }

    @Test func timeBonusShrinksWithTheTimeUsed() {
        let early = deliver(1, time: 600).0.tally.timeBonus
        let m = makeMission(people: 1, timeLimit: 600)   // somebody waits far away, so the Einsatz runs on
        var late = MissionSimulation(mission: m)
        steps(&late, seconds: 450)   // three quarters gone
        late.debugSetPeople(aboard: 1)
        late.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: late.spec.maxDurability))
        steps(&late, seconds: 3)
        // Three quarters of the time are gone (plus the few seconds of the delivery): about a quarter of the bonus.
        #expect(late.tally.timeBonus < early)
        #expect(abs(late.tally.timeBonus - Int((Double(Scoring.timeBonusMax) * 0.25).rounded())) <= 1)
    }

    @Test func damageCutsTheChain() {
        var m = makeMission(people: 0); m.rescuePoints = []
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: 6)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability))
        var events: [SimEvent] = []
        var t = 0.0
        var hit = false
        while t < 12 {
            events += sim.step(input: PilotInput(), dt: 1.0 / 60); t += 1.0 / 60
            if !hit, sim.tally.combo == 3 {
                hit = true
                var h = sim.heli; h.durability -= 10; sim.debugPlaceHelicopter(h)
            }
        }
        #expect(events.contains(.comboBroken(was: 3)))
        #expect(sim.tally.bestCombo == 3 && sim.tally.combo == 3)   // 3, broken, then 3 more
    }

    @Test func repairInTheCampDoesNotCutTheChain() {
        var m = makeMission(people: 0); m.rescuePoints = []
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: 4)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability * 0.5))
        steps(&sim, seconds: 8)
        #expect(sim.tally.combo == 4)
    }

    @Test func aLostPersonCutsTheChain() {
        // Three people are brought home, then the rising water takes the one still waiting on the roof.
        var m = makeMission(flood: FloodSpec(startLevel: -100, risePerSecond: 12, maxLevel: 500), people: 1)
        m.rescuePoints[0].top = 100
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: 3)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability))
        steps(&sim, seconds: 4)
        #expect(sim.tally.combo == 3 && sim.lostCount == 0)
        var events: [SimEvent] = []
        for _ in 0..<(60 * 16) { events += sim.step(input: PilotInput(up: true), dt: 1.0 / 60) }
        #expect(sim.lostCount == 1)
        #expect(sim.tally.combo == 0 && sim.tally.bestCombo == 3)
        #expect(events.contains(.comboBroken(was: 3)))
    }

    @Test func flightBonusForFullCabinAndForEverybodyAtOnce() {
        let full = deliver(12).1.compactMap { e -> (Int, Bool)? in if case .flightBonus(let p, _, let a) = e { return (p, a) } else { return nil } }
        #expect(full.count == 1)
        // 12 people aboard, 12 in all, capacity 12: everybody in one flight beats the full cabin.
        #expect(full[0] == (Scoring.allInOneFlightBonus, true))
        // Full cabin while more people exist elsewhere.
        var m = makeMission(people: 5, capacity: 6)
        m.rescuePoints[0].x = 500
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: 6)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability))
        var ev: [SimEvent] = []
        for _ in 0..<(60 * 4) { ev += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(ev.contains(.flightBonus(points: Scoring.fullCabinBonus, people: 6, all: false)))
        // A small delivery gets nothing, and one flight is paid once.
        #expect(!deliver(3, others: 2).1.contains { if case .flightBonus = $0 { return true } else { return false } })
        #expect(deliver(12).1.filter { if case .flightBonus = $0 { return true } else { return false } }.count == 1)
    }

    @Test func resultAddsUpAndStarsIgnoreTheBonuses() {
        var m = makeMission(people: 0, helicopters: 3, timeLimit: 600); m.rescuePoints = []
        var sim = MissionSimulation(mission: m)
        sim.debugSetPeople(aboard: 4)
        sim.debugPlaceHelicopter(HelicopterState(x: 1500, y: 0, fuel: 100, durability: sim.spec.maxDurability))
        steps(&sim, seconds: 20)
        let r = sim.result!
        #expect(r.outcome == .completed && r.rescued == 4 && r.stars == 3)
        #expect(r.score == 4 * 100 + r.timeBonus + r.comboBonus + r.flightBonus + Int(sim.timeLeft))
        #expect(r.score > 4 * 100 + Int(sim.timeLeft))   // never below the old formula
        #expect(r.bestCombo == 4)
        #expect(sim.livePoints == r.score - Int(sim.timeLeft))
    }
}
