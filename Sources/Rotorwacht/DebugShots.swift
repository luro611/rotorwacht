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
        // ROTORWACHT_HOVER=x,y: fly there and stay, to look at a hazard from close by.
        let hover = ProcessInfo.processInfo.environment["ROTORWACHT_HOVER"]?.split(separator: ",").compactMap { Double($0) }
        script = { _ in
            guard let sim = model.scene?.sim else { return PilotInput() }
            guard let hv = hover, hv.count == 2 else { return pilot.input(for: sim) }
            let h = sim.heli
            var input = PilotInput()
            let vx = max(-230, min(230, (hv[0] - h.x) * 0.8))
            if h.vx < vx - 12 { input.right = true } else if h.vx > vx + 12 { input.left = true }
            let wantY = abs(hv[0] - h.x) > 80 ? max(hv[1], 460) : hv[1]   // over the roofs first, then down
            let vy = max(-100, min(100, (wantY - h.y) * 1.4))
            if vy > h.vy + 8 { input.up = true } else if vy < h.vy - 8 { input.down = true }
            return input
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
        let defaults: [String: [Double]] = [
            "hochwasser": [4, 14, 26, 60, 95],
            "waldbrand": [14, 17, 20, 23, 26, 29, 33, 37, 42, 50, 60],
        ]
        let custom = ProcessInfo.processInfo.environment["ROTORWACHT_TIMES"]?.split(separator: ",").compactMap { Double($0) }
        let list = custom ?? defaults[missionID] ?? [6, 20, 30, 45, 60, 80]
        for t in list {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + t) { snap(dir, "\(missionID)-t\(Int(t))", window: false, model: model) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0 + (list.max() ?? 90) + 4) { NSApp.terminate(nil) }
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
