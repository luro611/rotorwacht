import Testing
import Foundation
@testable import RotorwachtCore

/// 0.4.0: every person stands on a pad, every pad is flat and wide enough for the skids, in all missions.
@Suite struct PadTests {
    static let skid = HelicopterSpec.standard.halfWidth * 2

    private func all() throws -> [Mission] { try MissionLibrary.all.map { try MissionLibrary.load($0) } }

    @Test func everyLandingPadIsAtLeastAsWideAsTheSkids() throws {
        for m in try all() {
            for p in m.rescuePoints where !p.isWinch {
                #expect(p.width >= Self.skid + 16, "\(m.id)/\(p.id): Fläche \(p.width) schmaler als Kufen \(Self.skid)")
            }
        }
    }

    @Test func padSurfaceIsFlatAcrossItsWidth() throws {
        for m in try all() {
            for p in m.rescuePoints {
                for i in 0...20 {
                    let x = p.x - p.width / 2 + p.width * Double(i) / 20
                    #expect(near(m.surfaceHeight(at: x), p.top, 0.01), "\(m.id)/\(p.id): Fläche nicht eben bei x=\(x)")
                    // Ground pads and ledges sit exactly on the terrain: no floating, no burying.
                    if p.kind == "island" || p.kind == "ledge" {
                        #expect(near(m.groundHeight(at: x), p.top, 0.6), "\(m.id)/\(p.id): Gelände \(m.groundHeight(at: x)) ≠ Fläche \(p.top)")
                    } else if p.kind != "boat" {
                        #expect(m.groundHeight(at: x) <= p.top, "\(m.id)/\(p.id): Gelände über der Landefläche")
                    }
                }
            }
        }
    }

    @Test func everyPersonStandsOnTheirPadAtTheEdge() throws {
        for m in try all() {
            let sim = MissionSimulation(mission: m)
            for person in sim.people {
                let p = m.rescuePoints[person.pointIndex]
                #expect(abs(person.spotX - p.x) <= p.width / 2, "\(m.id)/\(p.id): Person außerhalb der Fläche")
                #expect(near(m.surfaceHeight(at: person.spotX), p.top, 0.01), "\(m.id)/\(p.id): Person nicht auf der Fläche")
            }
            for (pi, p) in m.rescuePoints.enumerated() where !p.isWinch {
                let xs = sim.people.filter { $0.pointIndex == pi }.map { abs($0.spotX - p.x) }
                // The first two (one per side) stand clear of the skids.
                for d in xs.prefix(2) { #expect(d >= HelicopterSpec.standard.halfWidth, "\(m.id)/\(p.id): Person unter den Kufen") }
            }
        }
    }

    @Test func everyPadHasARenderedSprite() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Rotorwacht/Renders/pads/pads.json")
        let data = try Data(contentsOf: url)
        let meta = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(meta["pad-camp"] != nil)
        for m in try all() {
            for p in m.rescuePoints { #expect(meta["pad-\(m.id)-\(p.id)"] != nil, "Sprite fehlt: \(m.id)/\(p.id)") }
        }
    }

    @Test func everyPassageHasARenderedStructure() throws {
        let dir = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Rotorwacht/Renders/passages")
        for m in try all() {
            for p in m.passageList {
                #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("mass-\(m.id)-\(p.id).png").path), "Bild fehlt: \(m.id)/\(p.id)")
            }
        }
    }
}
