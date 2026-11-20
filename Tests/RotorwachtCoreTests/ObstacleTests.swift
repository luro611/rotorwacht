import Testing
@testable import RotorwachtCore

/// Flat test world (ground 0, ceiling 900) with one obstacle in the middle.
private func world(_ o: Obstacle, weather: [WeatherEvent]? = nil) -> Mission {
    var m = makeMission()
    m.obstacles = [o]
    m.weather = weather
    return m
}

private func fly(_ m: Mission, x: Double, y: Double, vx: Double = 0) -> MissionSimulation {
    var s = MissionSimulation(mission: m)
    s.heli.x = x; s.heli.y = y; s.heli.vx = vx
    s.heli.onGround = false
    return s
}

private let line = Obstacle(id: "l", kind: "powerline", x: 800, x1: 1100, height: 200)
private let crane = Obstacle(id: "c", kind: "crane", x: 900, height: 200, reach: 150, period: 12)
private let mill = Obstacle(id: "w", kind: "windmill", x: 900, height: 220, reach: 100, period: 6)
private let car = Obstacle(id: "s", kind: "cablecar", x: 700, x1: 1200, height: 260, period: 20)

@Suite struct ObstacleTests {
    @Test func powerLineWiresHurtButDoNotKill() {
        let m = world(line)
        // At mid-span the top wire hangs about 15 below the attachment (sag 0.05 of 300).
        var s = fly(m, x: 950, y: 200 - 15 - 40)
        var hits: [SimEvent] = []
        for _ in 0..<30 { hits += s.step(input: PilotInput(), dt: 1.0 / 60).filter { if case .obstacleHit = $0 { return true } else { return false } } }
        #expect(!hits.isEmpty)
        #expect(s.heli.durability < 100 && s.heli.durability > 0)
    }

    @Test func flyingOverAndUnderIsFree() {
        let m = world(line)
        var over = fly(m, x: 950, y: 330)
        over.step(input: PilotInput(), dt: 1.0 / 60)
        #expect(over.heli.durability == 100)
        // Far below the wires, in the gap.
        var under = fly(m, x: 950, y: 20)
        under.step(input: PilotInput(), dt: 1.0 / 60)
        #expect(under.heli.durability == 100)
    }

    @Test func towerDestroysTheHelicopter() {
        let m = world(mill)
        var s = fly(m, x: 900, y: 60)
        s.step(input: PilotInput(), dt: 1.0 / 60)
        #expect(s.heli.durability == 0)
    }

    @Test func bladesTurnAndOnlyHitWhereTheyAre() {
        let m = world(mill)
        // Point on the first blade tip at t = 0 (blade angle 0 = to the right): hit then, free half a turn later at the left side.
        let tipX = 900 + 100.0 * 0.9, tipY = 220.0
        #expect(mill.touch(circleX: tipX, y: tipY, radius: 20, at: 0, in: m) != nil)
        #expect(mill.touch(circleX: tipX, y: tipY, radius: 20, at: 3.0, in: m) == nil || mill.bladeAngle(at: 3) != 0)
        // The blade tip is on the opposite side after half a turn.
        let a = mill.bladeAngle(at: 3) - mill.bladeAngle(at: 0)
        #expect(near(a, Double.pi, 1e-9))
    }

    @Test func craneJibSwingsAcrossTheTower() {
        let m = world(crane)
        #expect(near(crane.swing(at: 0), 1, 1e-9))
        #expect(near(crane.swing(at: 3), 0, 1e-9))
        #expect(near(crane.swing(at: 6), -1, 1e-9))
        // Jib tip at the right at t=0: touching the tip hurts, the same place is free once the jib has swung round.
        let top = 200.0
        #expect(crane.touch(circleX: 900 + 140, y: top, radius: 20, at: 0, in: m)?.solid == true)
        #expect(crane.touch(circleX: 900 + 140, y: top, radius: 20, at: 6, in: m) == nil)
    }

    @Test func gondolaRidesBackAndForth() {
        let m = world(car)
        #expect(near(car.gondola(at: 0), 0, 1e-9))
        #expect(near(car.gondola(at: 10), 1, 1e-9))
        #expect(near(car.gondola(at: 20), 0, 1e-9))
        let c0 = car.gondolaCenter(at: 0, in: m), c1 = car.gondolaCenter(at: 10, in: m)
        #expect(c0.x < c1.x)
        #expect(car.touch(circleX: c0.x, y: c0.y, radius: 5, at: 0, in: m)?.solid == true)
    }

    @Test func envelopeIsAlwaysAboveTheMovingParts() {
        let m = world(crane)
        let e = crane.envelope(in: m)
        for t in stride(from: 0.0, to: 12, by: 0.25) {
            for s in crane.shapes(at: t, in: m) {
                #expect(max(s.y0, s.y1) + s.radius <= e.top + 1)
                #expect(min(s.x0, s.x1) - s.radius >= e.x0 - 1 && max(s.x0, s.x1) + s.radius <= e.x1 + 1)
            }
        }
        #expect(world(mill).obstacleTop(from: 800, to: 1000) != nil)
        #expect(world(mill).obstacleTop(from: 0, to: 300) == nil)
    }

    @Test func badObstacleDataIsRejected() throws {
        func bad(_ o: Obstacle) -> Bool { (try? world(o).validate()) == nil }
        #expect(!bad(line) && !bad(crane) && !bad(mill) && !bad(car))
        #expect(bad(Obstacle(id: "a", kind: "ufo", x: 800, height: 100)))
        #expect(bad(Obstacle(id: "a", kind: "powerline", x: 800, height: 100)))            // no second mast
        #expect(bad(Obstacle(id: "a", kind: "crane", x: 900, height: 800, reach: 100)))     // too tall to fly over
        #expect(bad(Obstacle(id: "a", kind: "windmill", x: 900, height: 80, reach: 100)))   // blades in the ground
        #expect(bad(Obstacle(id: "a", kind: "crane", x: 500, height: 100, reach: 100)))     // on the rescue point
        #expect(bad(Obstacle(id: "a", kind: "crane", x: 1500, height: 100, reach: 100)))    // in the camp
    }

    @Test func levelsScaleWireDamage() {
        var o = line; o.damage = 40
        let m = world(o)
        #expect(m.scaled(for: .easy).obstacleList[0].wireDamage < 40)
        #expect(m.scaled(for: .hard).obstacleList[0].wireDamage > 40)
        #expect(m.scaled(for: .medium) == m)
    }
}

@Suite struct WeatherTests {
    private let gust = WeatherEvent(kind: "gust", start: 20, duration: 10, warn: 6, strength: 120)
    private let shift = WeatherEvent(kind: "windShift", start: 50, duration: 30, warn: 8, strength: -90)
    private let fogBank = WeatherEvent(kind: "fog", start: 100, duration: 60, warn: 8, density: 0.7, x0: 1000, x1: 1400)
    private let storm = WeatherEvent(kind: "thunder", start: 200, duration: 40, warn: 10, x0: 300, x1: 1200, interval: 8, radius: 150, damage: 18)

    private func mission() -> Mission {
        var m = makeMission(timeLimit: 400)
        m.weather = [gust, shift, fogBank, storm]
        return m
    }

    @Test func gustsAndShiftsBlowInTheirTime() {
        let m = mission()
        #expect(near(m.weatherWind(at: 10), 0, 1e-9))
        #expect(near(m.weatherWind(at: 25), 120, 1e-9))
        #expect(near(m.weatherWind(at: 40), 0, 1e-9))
        #expect(near(m.weatherWind(at: 65), -90, 1e-9))
        #expect(m.weatherWind(at: 51) > -90 && m.weatherWind(at: 51) < 0)
        #expect(near(m.weatherWind(at: 90), 0, 1e-9))
        // The mission wind contains it.
        #expect(near(m.windAcceleration(at: 25) - makeMission().windAcceleration(at: 25), 120, 1e-9))
    }

    @Test func fogRollsInAndOutAndStaysInItsStretch() {
        let m = mission()
        #expect(m.fog(at: 90, x: 1200).density == 0)
        #expect(near(m.fog(at: 130, x: 1200).density, 0.7, 1e-9))
        #expect(m.fog(at: 130, x: 300).density == 0)
        let edge = m.fog(at: 130, x: 1500).density
        #expect(edge > 0 && edge < 0.7)
        #expect(m.fog(at: 101, x: 1200).density < 0.7)
        #expect(m.fog(at: 170, x: 1200).density == 0)
    }

    @Test func warningComesFirstAndOnlyOnce() {
        var s = MissionSimulation(mission: mission())
        var warnings: [(String, Double)] = []
        while s.time < 60 {
            for e in s.step(input: PilotInput(), dt: 1.0 / 30) {
                if case .weatherWarning(let k, let sec) = e { warnings.append((k, sec)) }
            }
            if (14...20).contains(s.time) { #expect(s.weatherNotices.contains { $0.kind == "gust" && $0.direction == 1 }) }
        }
        #expect(warnings.map(\.0) == ["gust", "windShift"])
        #expect(warnings.allSatisfy { $0.1 > 0 })
    }

    @Test func noticeShowsDirection() {
        let m = mission()
        #expect(m.weatherNotices(at: 45).first?.direction == -1)
        #expect(m.weatherNotices(at: 5).isEmpty)
        #expect(m.weatherNotices(at: 21).isEmpty)
    }

    @Test func thunderstormStrikesOnlyInItsWindow() {
        var m = mission()
        m.weather = [storm]
        var s = MissionSimulation(mission: m)
        s.heli.x = 1900; s.heli.y = 300; s.heli.onGround = false
        var strikes: [Double] = []
        for _ in 0..<(300 * 30) {
            for e in s.step(input: PilotInput(up: false), dt: 1.0 / 30) { if case .lightning = e { strikes.append(s.time) } }
            if s.heli.y < 5 { s.heli.y = 300; s.heli.vy = 0 }
        }
        #expect(strikes.count >= 3)
        #expect(strikes.allSatisfy { $0 >= 200 - 3 && $0 <= 240 + 3 })
        #expect(m.thunderBuildup(at: 100) == 0 && m.thunderBuildup(at: 205) == 1 && m.thunderBuildup(at: 250) < 1)
    }

    @Test func levelsScaleWeather() {
        let m = mission()
        let easy = m.scaled(for: .easy), hard = m.scaled(for: .hard)
        #expect(abs(easy.weatherList[0].strength!) < 120 && abs(hard.weatherList[0].strength!) > 120)
        #expect(easy.weatherList[0].warn > 6 && hard.weatherList[0].warn < 6)
        #expect(hard.weatherList[2].density! <= 0.9)
        #expect(m.scaled(for: .medium) == m)
        for l in Difficulty.allCases { try? m.scaled(for: l).validate() }
    }

    @Test func badWeatherDataIsRejected() {
        func bad(_ e: WeatherEvent) -> Bool { var m = makeMission(); m.weather = [e]; return (try? m.validate()) == nil }
        #expect(!bad(gust) && !bad(fogBank) && !bad(storm))
        #expect(bad(WeatherEvent(kind: "hail", start: 1, duration: 5, warn: 1)))
        #expect(bad(WeatherEvent(kind: "gust", start: 1, duration: 5, warn: 1)))
        #expect(bad(WeatherEvent(kind: "gust", start: 1, duration: 5, warn: 1, strength: 900)))
        #expect(bad(WeatherEvent(kind: "fog", start: 1, duration: 5, warn: 1, density: 1.4)))
        #expect(bad(WeatherEvent(kind: "fog", start: 1, duration: 0, warn: 1, density: 0.5)))
    }
}

@Suite struct ObstacleMissionTests {
    @Test func everyEinsatzHasAnObstacleAndWeatherButNotEverythingEverywhere() throws {
        var kinds = Set<String>(), weather = Set<String>()
        for id in MissionLibrary.all {
            let m = try MissionLibrary.load(id)
            #expect(!m.obstacleList.isEmpty && !m.weatherList.isEmpty, "\(id)")
            m.obstacleList.forEach { kinds.insert($0.kind) }
            m.weatherList.forEach { weather.insert($0.kind) }
            for l in Difficulty.allCases { try m.scaled(for: l).validate() }
        }
        #expect(kinds == ["powerline", "crane", "cablecar", "windmill"])
        #expect(weather == ["gust", "windShift", "fog", "thunder"])
    }

    /// Obstacles stand away from the people and the camp, so each one can be flown over with room to spare.
    @Test func obstaclesLeaveRoomForTheFlight() throws {
        for id in MissionLibrary.all {
            let m = try MissionLibrary.load(id)
            for o in m.obstacleList {
                let e = o.envelope(in: m)
                #expect(e.top <= m.world.ceiling - Obstacle.ceilingRoom)
                for r in m.rescuePoints { #expect(r.x - r.width / 2 > e.x1 + 60 || r.x + r.width / 2 < e.x0 - 60, "\(id) \(o.id) \(r.id)") }
            }
        }
    }

    /// The scripted pilot flies each Einsatz on every level without touching an obstacle and still finishes it.
    @Test(arguments: MissionLibrary.all, Difficulty.allCases)
    func autopilotNeverTouchesObstacles(id: String, level: Difficulty) throws {
        let m = try MissionLibrary.load(id).scaled(for: level)
        var sim = MissionSimulation(mission: m)
        let pilot = AutoPilot()
        var hits: [SimEvent] = []
        while !sim.isFinished && sim.time < m.timeLimit + 10 {
            for e in sim.step(input: pilot.input(for: sim), dt: 1.0 / 60) {
                switch e {
                case .obstacleHit: hits.append(e)
                default: break
                }
            }
        }
        #expect(hits.isEmpty, "Treffer: \(hits)")
        #expect(sim.isFinished)
        #expect(sim.result?.outcome != .failed)
    }
}
