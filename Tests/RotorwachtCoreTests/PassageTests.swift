import Testing
@testable import RotorwachtCore

/// Flat test world (ground 0) with a tunnel from 800 to 1300, roof 200, one door at 1000.
private func tunnelMission(period: Double = 10, open: Double = 4, phase: Double = 0, warn: Double = 1.5, gap: Double? = nil) -> Mission {
    var m = makeMission()
    m.passages = [Passage(id: "t", kind: "tunnel", x0: 800, x1: 1300, roof: 200,
                          shutters: [Shutter(x: 1000, period: period, open: open, phase: phase, warn: warn, gap: gap)])]
    return m
}

private func fly(_ m: Mission, x: Double, y: Double, vx: Double = 0, vy: Double = 0) -> MissionSimulation {
    var sim = MissionSimulation(mission: m)
    var h = HelicopterState(x: x, y: y, fuel: 100)
    h.vx = vx; h.vy = vy; h.onGround = false
    sim.debugPlaceHelicopter(h)
    return sim
}

@Suite struct PassageTests {
    @Test func doorRhythm() {
        let s = Shutter(x: 0, period: 10, open: 4, phase: 0, warn: 1.5)
        #expect(Passage.openness(s, at: 0) == 1)
        #expect(Passage.openness(s, at: 3.9) == 1)
        #expect(near(Passage.openness(s, at: 4.3), 0.5, 0.01))
        #expect(Passage.openness(s, at: 6) == 0)
        #expect(Passage.openness(s, at: 9.4) < 0.1)
        #expect(near(Passage.openness(s, at: 9.7), 0.5, 0.01))
        #expect(Passage.openness(s, at: 10.5) == 1)
        #expect(Passage.light(s, at: 1) == .green)
        #expect(Passage.light(s, at: 3) == .amber)
        #expect(Passage.light(s, at: 5) == .red)
        #expect(Passage.light(s, at: 9.9) == .red)
        #expect(Passage.light(s, at: 10.1) == .green)
        // A phase shifts the cycle.
        var shifted = s; shifted.phase = 6
        #expect(Passage.openness(shifted, at: 0) == 0)
        #expect(Passage.openness(shifted, at: 4) == 1)
    }

    @Test func warningAndClosingEventsComeOncePerCycle() {
        var sim = MissionSimulation(mission: tunnelMission())
        var warnings: [Double] = [], closings: [Double] = []
        for _ in 0..<(60 * 25) {
            for e in sim.step(input: PilotInput(), dt: 1.0 / 60) {
                if case .shutterWarning = e { warnings.append(sim.time) }
                if case .shutterClosing = e { closings.append(sim.time) }
            }
        }
        #expect(warnings.count == 3 && closings.count == 3)
        for (w, c) in zip(warnings, closings) { #expect(near(c - w, 1.5, 0.05)) }
        #expect(near(warnings[0], 2.5, 0.05) && near(warnings[1], 12.5, 0.05))
    }

    @Test func closedDoorDestroysTheHelicopter() {
        var sim = fly(tunnelMission(), x: 975, y: 60, vx: 100)
        var crushed = false
        for _ in 0..<(60 * 30) {   // flies into the door while it is closed (closed from 4.6 s)
            sim.debugPlaceHelicopter({ var h = sim.heli; if sim.time < 5 { h.x = 975; h.vx = 0 }; return h }())
            for e in sim.step(input: PilotInput(), dt: 1.0 / 60) { if case .shutterCrush = e { crushed = true } }
            if crushed { break }
        }
        #expect(crushed)
        #expect(sim.helicoptersLeft == 2)
    }

    @Test func doorClosingOnTheHelicopterCrushesIt() {
        // Hovering in the doorway when the door comes down.
        var sim = fly(tunnelMission(), x: 1000, y: 60)
        var crushed = false
        for _ in 0..<(60 * 6) {
            sim.debugPlaceHelicopter({ var h = sim.heli; h.x = 1000; h.y = 60; h.vx = 0; h.vy = 0; h.onGround = false; return h }())
            for e in sim.step(input: PilotInput(), dt: 1.0 / 60) { if case .shutterCrush = e { crushed = true } }
        }
        #expect(crushed)
    }

    @Test func openDoorLetsTheHelicopterThrough() {
        var sim = fly(tunnelMission(period: 40, open: 30), x: 700, y: 60, vx: 150)
        var hit = false
        for _ in 0..<(60 * 8) {
            sim.debugPlaceHelicopter({ var h = sim.heli; h.y = 60; h.vy = 0; h.vx = 150; h.onGround = false; return h }())
            for e in sim.step(input: PilotInput(), dt: 1.0 / 60) {
                if case .shutterCrush = e { hit = true }
                if case .passageContact = e { hit = true }
            }
        }
        #expect(!hit)
        #expect(sim.heli.x > 1300)
        #expect(sim.helicoptersLeft == 3)
    }

    @Test func roofStopsAndHurts() {
        var sim = fly(tunnelMission(period: 40, open: 30), x: 1150, y: 100, vy: 120)
        var contact = false
        for _ in 0..<60 {
            for e in sim.step(input: PilotInput(up: true), dt: 1.0 / 60) { if case .passageContact(let k, _) = e, k == "roof" { contact = true } }
        }
        #expect(contact)
        #expect(sim.heli.y + Passage.heliHeight <= 200.001)
        #expect(sim.heli.durability < 100)
    }

    @Test func passagesCannotBeFlownOver() {
        // High and fast against the end wall: stopped in front, damaged, never above the roof inside the span.
        var sim = fly(tunnelMission(period: 40, open: 30), x: 600, y: 400, vx: 250)
        for _ in 0..<(60 * 6) {
            sim.debugPlaceHelicopter({ var h = sim.heli; h.y = 400; h.vy = 0; h.onGround = false; return h }())
            sim.step(input: PilotInput(right: true), dt: 1.0 / 60)
            #expect(sim.heli.x <= 800 - Passage.bodyHalfWidth + 0.001)
        }
        #expect(sim.heli.durability < 100)
    }

    @Test func fallingObjectsOverThePassageAreGone() {
        var m = tunnelMission()
        m.volleys = [Volley(kind: "debris", start: 0, interval: 1, repeats: 1, count: 1, stagger: 0, x0: 1100, x1: 1100, spawnY: 500,
                            speedMin: 0, speedMax: 0, angleMin: 0, angleMax: 0, gravity: 100, warn: 0, radius: 20, damage: 10, blockTime: 0)]
        var sim = MissionSimulation(mission: m)
        steps(&sim, seconds: 1)
        #expect(sim.hz.objects.isEmpty && sim.hz.rubble.isEmpty)
    }

    @Test func groundFlowsDoNotReachIntoATunnel() {
        var m = tunnelMission(period: 40, open: 30)
        m.flows = [Flow(id: "f", kind: "avalanche", start: 0, warn: 0, x0: 700, x1: 1400, speed: 50, length: 600, damagePerSecond: 50, clearance: 120)]
        var sim = fly(m, x: 1100, y: 60)
        for _ in 0..<(60 * 6) {
            sim.debugPlaceHelicopter({ var h = sim.heli; h.x = 1100; h.y = 60; h.vx = 0; h.vy = 0; h.onGround = false; return h }())
            sim.step(input: PilotInput(), dt: 1.0 / 60)
        }
        #expect(sim.heli.durability == 100)
    }

    @Test func badPassageDataIsRejected() throws {
        var m = tunnelMission()
        m.passages![0].roof = 90                       // too low for the helicopter
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(); m.passages![0].shutters![0].x = 2000
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(period: 5, open: 4)         // no time to close and open
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(); m.passages![0].kind = "cave"
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(); m.passages![0].x1 = 700
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(); m.passages![0].x0 = 400; m.passages![0].x1 = 700   // rescue point at 500
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        m = tunnelMission(); m.passages![0].kind = "bridge"
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
        #expect(throws: Never.self) { try tunnelMission().validate() }
    }

    @Test func levelsScaleRhythmWarningAndOpening() throws {
        let m = try MissionLibrary.load("vulkan")
        let easy = m.scaled(for: .easy).passages![0], hard = m.scaled(for: .hard).passages![0], mid = m.passages![0]
        let floor = mid.floorRef(in: m)
        #expect(easy.shutters![0].open > mid.shutters![0].open && hard.shutters![0].open < mid.shutters![0].open)
        #expect(easy.shutters![0].warn > mid.shutters![0].warn && hard.shutters![0].warn < mid.shutters![0].warn)
        #expect(easy.roof - floor > mid.roof - floor && hard.roof - floor < mid.roof - floor)
        #expect(hard.roof - floor >= Passage.heliHeight + Passage.minRoom)
        for level in Difficulty.allCases { try m.scaled(for: level).validate() }
        #expect(m.scaled(for: .medium) == m)
    }

    // MARK: The Einsätze

    @Test func theEinsaetzeWithPassagesHaveThemBetweenCampAndPeople() throws {
        let expected = ["hochwasser": "bridge", "altstadt": "bridge", "vulkan": "tunnel", "gebirge": "tunnel",
                        "staudamm": "bridge", "pass": "tunnel"]
        for id in MissionLibrary.all {
            let m = try MissionLibrary.load(id)
            guard let kind = expected[id] else { #expect(m.passageList.isEmpty); continue }
            let p = try #require(m.passageList.first)
            #expect(p.kind == kind)
            // The camp lies behind the passage, with people on the far side, so it cannot be avoided.
            #expect(m.rescuePoints.contains { $0.x + $0.width / 2 < p.x0 })
            #expect(m.base.x - m.base.width / 2 > p.x1)
            #expect(p.isTunnel == !p.shutterList.isEmpty)
        }
    }

    /// For every Einsatz, level and direction a window exists in which the doors can be crossed, and it comes soon enough.
    @Test(arguments: MissionLibrary.all, Difficulty.allCases)
    func aWindowToCrossExists(id: String, level: Difficulty) throws {
        let m = try MissionLibrary.load(id).scaled(for: level)
        for p in m.passageList {
            for dir in [1.0, -1.0] {
                let start = dir > 0 ? p.x0 - 170 : p.x1 + 170
                var first: Double?
                var t = 0.0
                while t < 40 {
                    if p.canCross(in: m, flood: m.floodLevel(at: t), from: start, direction: dir, at: t) { first = t; break }
                    t += 0.1
                }
                let f = try #require(first, "kein Fenster in \(id) \(level) \(dir)")
                #expect(f < 20, "Wartezeit zu lang")
            }
        }
    }

    /// The scripted pilot flies the passages without a single hit.
    @Test(arguments: ["hochwasser", "altstadt", "vulkan", "gebirge", "staudamm", "pass"], Difficulty.allCases)
    func autopilotCrossesWithoutHits(id: String, level: Difficulty) throws {
        let m = try MissionLibrary.load(id).scaled(for: level)
        var sim = MissionSimulation(mission: m)
        let pilot = AutoPilot()
        var contacts: [SimEvent] = []
        var crossings = 0
        var side = true
        while !sim.isFinished && sim.time < m.timeLimit + 10 {
            for e in sim.step(input: pilot.input(for: sim), dt: 1.0 / 60) {
                switch e {
                case .shutterCrush, .passageContact: contacts.append(e)
                default: break
                }
            }
            if sim.heli.x < m.passageList[0].x0 && side { crossings += 1; side = false }
            if sim.heli.x > m.passageList[0].x1 && !side { crossings += 1; side = true }
        }
        #expect(contacts.isEmpty, "Treffer: \(contacts)")
        #expect(crossings >= 2, "Durchfahrt wurde nicht geflogen")
    }
}
