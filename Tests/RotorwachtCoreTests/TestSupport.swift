import Testing
@testable import RotorwachtCore

/// A tiny flat mission for exact tests: ground at 0 from 0 to 2000, a rooftop at x=500 (top 100), base at x=1500.
func makeMission(flood: FloodSpec = FloodSpec(startLevel: -100, risePerSecond: 0, maxLevel: -100),
                 people: Int = 3, capacity: Int = 12, helicopters: Int = 3, timeLimit: Double = 600) -> Mission {
    Mission(
        id: "test", title: "Test", briefing: "",
        world: WorldSpec(width: 2000, ceiling: 900),
        terrain: [TerrainPoint(x: 0, y: 0), TerrainPoint(x: 2000, y: 0)],
        base: BaseSpec(x: 1500, width: 300),
        rescuePoints: [RescuePointSpec(id: "a", name: "A", kind: "roof", x: 500, width: 160, top: 100, people: people)],
        helicopters: helicopters, capacity: capacity, timeLimit: timeLimit,
        fuel: FuelSpec(capacity: 100, burnPerSecond: 0.5, refuelPerSecond: 20),
        flood: flood,
        wind: WindSpec(base: 0, gusts: []))
}

func steps(_ sim: inout MissionSimulation, _ input: PilotInput = PilotInput(), seconds: Double, dt: Double = 1.0 / 60) {
    var t = 0.0
    while t < seconds { sim.step(input: input, dt: dt); t += dt }
}

func near(_ a: Double, _ b: Double, _ accuracy: Double) -> Bool { abs(a - b) <= accuracy }
