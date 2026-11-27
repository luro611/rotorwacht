import Testing
import Foundation
@testable import RotorwachtCore

/// Building blocks of 0.9.0: swaying decks, icing, heat and the flood wave.
@Suite struct ClimateTests {
    private func deckMission() -> Mission {
        var m = makeMission()
        m.rescuePoints[0].heave = HeaveSpec(amplitude: 20, period: 4)
        return m
    }

    @Test func aLandedHelicopterRidesTheSwayingDeck() throws {
        let m = deckMission()
        try m.validate()
        var sim = MissionSimulation(mission: m)
        sim.debugPlaceHelicopter(HelicopterState(x: 500, y: 100, fuel: 100))
        var low = 1e9, high = -1e9
        for _ in 0..<(8 * 60) {
            sim.step(input: PilotInput(), dt: 1.0 / 60)
            #expect(sim.heli.onGround && sim.heli.durability == 100)
            #expect(near(sim.heli.y, sim.live.rescuePoints[0].top, 0.01))
            low = min(low, sim.heli.y); high = max(high, sim.heli.y)
        }
        #expect(near(low, 80, 1) && near(high, 120, 1))
        #expect(sim.rescuedCount == 0 && sim.aboardCount == 3)   // people board while the deck moves
    }

    @Test func theDeckMustStayDry() {
        var m = deckMission()
        m.flood = FloodSpec(startLevel: 85, risePerSecond: 0, maxLevel: 85)
        #expect(throws: Mission.ValidationError.self) { try m.validate() }
    }

    @Test func iceGrowsInTheAirAndThawsInTheCamp() {
        var m = makeMission()
        m.icing = IcingSpec(rate: 0.1, thaw: 0.5, start: 1)
        var sim = MissionSimulation(mission: m)
        var air = HelicopterState(x: 900, y: 400, fuel: 100)
        air.onGround = false
        sim.debugPlaceHelicopter(air)
        var events: [SimEvent] = []
        for _ in 0..<(8 * 60) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.ice > 0.6 && events.contains(.iced))
        #expect(sim.flownSpec.horizontalAcceleration < sim.spec.horizontalAcceleration * 0.75)
        sim.debugPlaceHelicopter(HelicopterState(x: m.base.x, y: 0, fuel: 100))
        for _ in 0..<(3 * 60) { events += sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.ice == 0 && events.contains(.deiced))
    }

    @Test func heatCostsFuelAndClimb() {
        var m = makeMission()
        m.heatwave = HeatSpec(base: 0.4, pulses: [GustSpec(start: 10, duration: 10, strength: 0.4)])
        #expect(near(m.swelter(at: 0), 0.4, 1e-9) && near(m.swelter(at: 15), 0.8, 1e-9))
        var sim = MissionSimulation(mission: m)
        sim.step(input: PilotInput(), dt: 1.0 / 60)
        #expect(near(sim.fuelBurn, m.fuel.burnPerSecond * 1.4, 1e-9))
        #expect(sim.flownSpec.climbSpeed < sim.spec.climbSpeed)
    }

    @Test func levelsScaleTheNewBlocks() throws {
        let pass = try MissionLibrary.load("pass"), desert = try MissionLibrary.load("wueste"), rig = try MissionLibrary.load("bohrinsel")
        #expect(pass.scaled(for: .pro).icing!.rate > pass.icing!.rate && pass.scaled(for: .beginner).icing!.rate < pass.icing!.rate)
        #expect(desert.scaled(for: .pro).heatwave!.base > desert.heatwave!.base)
        #expect(rig.scaled(for: .beginner).rescuePoints[1].heave!.amplitude < rig.rescuePoints[1].heave!.amplitude)
    }

    /// Under a bridge the flood wave reaches the helicopter; only a tunnel shelters.
    @Test func aBridgeDoesNotShelterFromTheFloodWave() throws {
        let m = try MissionLibrary.load("staudamm")
        let p = m.passageList[0]
        var sim = MissionSimulation(mission: m)
        let x = (p.x0 + p.x1) / 2
        let start = m.flowList[0].start + (x - m.flowList[0].x0) / m.flowList[0].speed + 3
        while sim.time < start {
            sim.debugPlaceHelicopter(HelicopterState(x: m.base.x, y: m.baseSurface, fuel: 100))
            sim.step(input: PilotInput(), dt: 1.0 / 30)
        }
        sim.debugPlaceHelicopter(HelicopterState(x: x, y: m.surfaceHeight(at: x), fuel: 100))
        for _ in 0..<60 { sim.step(input: PilotInput(), dt: 1.0 / 60) }
        #expect(sim.heli.durability < 90)
    }

    @Test func theNewEinsaetzeUseTheirBlocks() throws {
        let rig = try MissionLibrary.load("bohrinsel")
        #expect(rig.heaves && rig.fire != nil && rig.rescuePoints.contains(where: \.isWinch) && !rig.stormList.isEmpty)
        let dam = try MissionLibrary.load("staudamm")
        #expect(dam.flowList.contains { $0.kind == "surge" } && dam.passageList.count == 2)
        let pass = try MissionLibrary.load("pass")
        #expect(pass.icing != nil && !pass.outpostList.isEmpty && pass.passageList.first?.isTunnel == true)
        #expect(pass.weatherList.contains { $0.tint == "snow" })
        let desert = try MissionLibrary.load("wueste")
        #expect(desert.heatwave != nil && !desert.outpostList.isEmpty && desert.weatherList.contains { $0.tint == "sand" })
    }
}
