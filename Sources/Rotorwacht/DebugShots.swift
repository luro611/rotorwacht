import AppKit
import SwiftUI
import SpriteKit
import RotorwachtCore

/// Developer aid: `ROTORWACHT_SHOTS=<dir>` starts the mission by itself, flies a short scripted route and
/// writes screenshots of the window and of the game scene, then quits. Not used in normal play.
enum DebugShots {
    static let active = ProcessInfo.processInfo.environment["ROTORWACHT_SHOTS"] != nil
    static var script: ((Double) -> PilotInput)?
    private static var t0 = Date()

    @MainActor static func runIfRequested(model: AppModel) {
        guard let dir = ProcessInfo.processInfo.environment["ROTORWACHT_SHOTS"] else { return }
        let missionID = ProcessInfo.processInfo.environment["ROTORWACHT_MISSION"] ?? MissionLibrary.all[0]
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        t0 = Date()
        let pilot = AutoPilot(fireFirst: missionID == "waldbrand")
        script = { _ in
            guard let sim = model.scene?.sim else { return PilotInput() }
            return pilot.input(for: sim)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            snap(dir, "0-start", window: true, model: model)
            let r = MissionResult(outcome: .completed, total: 28, rescued: 25, lost: 3, injured: 0, timeUsed: 301,
                                  helicoptersLost: 1, score: 2570, stars: 2)
            for (name, view) in [("result", AnyView(ResultOverlay(result: r, mission: model.loadMission(missionID)))), ("pause", AnyView(PauseOverlay()))] {
                let content = ZStack { Color.gray; view }.environmentObject(model).frame(width: 1280, height: 720)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/ui-\(name).png"))
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            MainActor.assumeIsolated { model.startMission(missionID) }
        }
        let times: [(Double, String)] = missionID == "waldbrand"
            ? [14, 17, 20, 23, 26, 29, 33, 37, 42, 50, 60].map { (Double($0), "t\($0)") }
            : [(4, "1-liftoff"), (14, "2-flying"), (26, "3-rescue"), (60, "4-return"), (95, "5-later")]
        for (t, name) in times {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + t) { snap(dir, name, window: false, model: model) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + (missionID == "waldbrand" ? 112.0 : 97.0)) { NSApp.terminate(nil) }
    }

    static var elapsed: Double { Date().timeIntervalSince(t0) - 3.0 }

    @MainActor static func snap(_ dir: String, _ name: String, window: Bool, model: AppModel) {
        if window, let w = NSApp.windows.first(where: { $0.contentView != nil }), let v = w.contentView {
            if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                v.cacheDisplay(in: v.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)-window.png"))
            }
        }
        for w in NSApp.windows {
            if let skView = find(SKView.self, in: w.contentView), let scene = skView.scene,
               let cg = skView.texture(from: scene)?.cgImage() {
                let rep = NSBitmapImageRep(cgImage: cg)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)-scene.png"))
                // Scene plus HUD, as the player sees it.
                let size = CGSize(width: 1280, height: 720)
                let content = ZStack {
                    Image(nsImage: NSImage(cgImage: cg, size: size)).resizable().frame(width: size.width, height: size.height)
                    HUDView(hud: model.hud).frame(width: size.width, height: size.height)
                }.frame(width: size.width, height: size.height)
                let renderer = ImageRenderer(content: content)
                renderer.scale = 1
                if let img = renderer.nsImage, let tiff = img.tiffRepresentation, let r2 = NSBitmapImageRep(data: tiff) {
                    try? r2.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "\(dir)/\(name)-game.png"))
                }
            }
        }
    }

    private static func find<T: NSView>(_ type: T.Type, in view: NSView?) -> T? {
        guard let view else { return nil }
        if let v = view as? T { return v }
        for s in view.subviews { if let r = find(type, in: s) { return r } }
        return nil
    }
}
