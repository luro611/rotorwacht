import SpriteKit
import RotorwachtCore

/// Draws the hazard building blocks of the simulation in world space: announced and falling lightning, falling and
/// flying objects with their flight paths, rubble, lava and avalanches. Rules live in RotorwachtCore.
final class HazardLayer: SKNode {
    private let mission: Mission
    private var beams: [Int: (beam: SKSpriteNode, ring: SKShapeNode)] = [:]
    private var bolts: [Int: SKSpriteNode] = [:]
    private var objects: [Int: (body: SKSpriteNode, path: SKShapeNode?, trail: Double)] = [:]
    private var rubble: [Int: SKSpriteNode] = [:]
    private var flowShapes: [SKShapeNode] = []
    private var flowGlow: [SKShapeNode] = []
    private var flowPuff: [Double] = []
    private var clock = 0.0
    private var boltTextures: [SKTexture] = []

    /// Called when lightning hits (the scene flashes the sky and plays thunder).
    var onThunder: ((CGFloat) -> Void)?

    init(mission: Mission) {
        self.mission = mission
        super.init()
        zPosition = 12
        for (i, f) in mission.flowList.enumerated() {
            let lava = f.kind == "lava"
            let surge = f.kind == "surge"
            let shape = SKShapeNode()
            shape.fillColor = lava ? SKColor(red: 1.0, green: 0.42, blue: 0.08, alpha: 0.96) : (surge ? SKColor(red: 0.27, green: 0.42, blue: 0.46, alpha: 0.92) : SKColor(red: 0.95, green: 0.97, blue: 1.0, alpha: 0.95))
            shape.strokeColor = lava ? SKColor(red: 1.0, green: 0.86, blue: 0.42, alpha: 1) : SKColor(white: 1, alpha: surge ? 0.75 : 1)
            shape.lineWidth = lava ? 3 : 2
            shape.zPosition = 2.5 + CGFloat(i) * 0.01
            shape.isHidden = true
            addChild(shape)
            flowShapes.append(shape)
            let glow = SKShapeNode()
            glow.fillColor = lava ? SKColor(red: 1.0, green: 0.5, blue: 0.1, alpha: 0.28) : (surge ? SKColor(red: 0.5, green: 0.68, blue: 0.72, alpha: 0.25) : SKColor(white: 1, alpha: 0.22))
            glow.strokeColor = .clear
            glow.zPosition = 2.4
            glow.isHidden = true
            addChild(glow)
            flowGlow.append(glow)
            flowPuff.append(0)
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    private func boltTexture(_ id: Int) -> SKTexture {
        if boltTextures.isEmpty { boltTextures = (0..<4).map { Art.bolt(height: 900, seed: UInt64(11 + $0 * 7)) } }
        return boltTextures[id % boltTextures.count]
    }

    private func floor(at x: Double, _ sim: MissionSimulation) -> Double {
        max(mission.surfaceHeight(at: x), mission.waterLevel(from: x, to: x, flood: sim.floodLevel))
    }

    func sync(sim: MissionSimulation, dt: Double, camX: CGFloat) {
        clock += dt
        syncStrikes(sim)
        syncObjects(sim, dt: dt)
        syncRubble(sim)
        syncFlows(sim, dt: dt, camX: camX)
    }

    // MARK: Lightning

    private func syncStrikes(_ sim: MissionSimulation) {
        var alive = Set<Int>()
        for s in sim.hz.strikes {
            alive.insert(s.id)
            let y = CGFloat(floor(at: s.x, sim))
            if s.age == nil {
                let cell = mission.stormList.first { s.x >= $0.x0 - 1 && s.x <= $0.x1 + 1 }
                let r = CGFloat(cell?.radius ?? 150)
                let n = beams[s.id] ?? {
                    let beam = SKSpriteNode(texture: Art.warnBeam(), size: CGSize(width: 24, height: 640))
                    beam.anchorPoint = CGPoint(x: 0.5, y: 0)
                    beam.zPosition = 15
                    addChild(beam)
                    let ring = SKShapeNode(ellipseOf: CGSize(width: r * 2, height: 26))
                    ring.strokeColor = SKColor(red: 1, green: 0.38, blue: 0.24, alpha: 0.9)
                    ring.fillColor = SKColor(red: 1, green: 0.38, blue: 0.24, alpha: 0.12)
                    ring.lineWidth = 2
                    ring.zPosition = 15
                    addChild(ring)
                    beams[s.id] = (beam, ring)
                    return (beam, ring)
                }()
                let pulse = CGFloat(0.6 + 0.4 * sin(clock * 14))
                n.beam.position = CGPoint(x: s.x, y: y)
                n.beam.alpha = pulse
                n.ring.position = CGPoint(x: s.x, y: y + 4)
                n.ring.alpha = pulse
            } else if bolts[s.id] == nil {
                if let b = beams[s.id] { b.beam.removeFromParent(); b.ring.removeFromParent(); beams[s.id] = nil }
                let bolt = SKSpriteNode(texture: boltTexture(s.id), size: CGSize(width: 140, height: 900))
                bolt.anchorPoint = CGPoint(x: 0.5, y: 0)
                bolt.position = CGPoint(x: s.x, y: y)
                bolt.zPosition = 16
                bolt.blendMode = .add
                addChild(bolt)
                bolts[s.id] = bolt
                onThunder?(CGFloat(s.x))
            }
            if let age = s.age, let b = bolts[s.id] { b.alpha = CGFloat(max(0, 1 - age / MissionSimulation.strikeFlash)) * (Int(age * 40) % 2 == 0 ? 1 : 0.6) }
        }
        for (id, b) in beams where !alive.contains(id) { b.beam.removeFromParent(); b.ring.removeFromParent(); beams[id] = nil }
        for (id, b) in bolts where !alive.contains(id) { b.removeFromParent(); bolts[id] = nil }
    }

    // MARK: Falling and flying objects

    private func syncObjects(_ sim: MissionSimulation, dt: Double) {
        var alive = Set<Int>()
        for o in sim.hz.objects {
            alive.insert(o.id)
            let lava = o.kind == "lavaBomb"
            var entry = objects[o.id]
            if entry == nil {
                let body: SKSpriteNode
                if lava {
                    body = SKSpriteNode(texture: Art.lavaBomb(), size: CGSize(width: o.radius * 2.6, height: o.radius * 2.6))
                } else {
                    body = SKSpriteNode(texture: Art.rock(), size: CGSize(width: o.radius * 2.2, height: o.radius * 2.2))
                    body.run(.repeatForever(.rotate(byAngle: CGFloat(o.id % 2 == 0 ? 5 : -5), duration: 1)))
                }
                body.zPosition = 11
                addChild(body)
                var path: SKShapeNode?
                if lava {
                    let p = SKShapeNode()
                    p.strokeColor = SKColor(red: 1, green: 0.55, blue: 0.2, alpha: 0.5)
                    p.lineWidth = 2
                    p.zPosition = 10
                    addChild(p)
                    path = p
                }
                entry = (body, path, 0)
            }
            var e = entry!
            e.body.position = CGPoint(x: o.x, y: o.y)
            if lava {
                let pts = ballisticPath(o, ground: { mission.surfaceHeight(at: $0) }, dt: 0.12, maxSteps: 70)
                let cg = CGMutablePath()
                cg.move(to: CGPoint(x: pts[0].x, y: pts[0].y))
                for p in pts.dropFirst() { cg.addLine(to: CGPoint(x: p.x, y: p.y)) }
                e.path?.path = cg.copy(dashingWithPhase: 0, lengths: [6, 8])
                e.trail -= dt
                if e.trail <= 0 {
                    e.trail = 0.05
                    let puff = SKSpriteNode(texture: Art.puff(), size: CGSize(width: 26, height: 26))
                    puff.color = SKColor(red: 1, green: 0.45, blue: 0.1, alpha: 1); puff.colorBlendFactor = 0.9
                    puff.alpha = 0.7; puff.position = e.body.position
                    addChild(puff)
                    puff.run(.sequence([.group([.fadeOut(withDuration: 0.6), .scale(to: 0.3, duration: 0.6)]), .removeFromParent()]))
                }
            }
            objects[o.id] = e
        }
        for (id, e) in objects where !alive.contains(id) {
            e.body.removeFromParent(); e.path?.removeFromParent(); objects[id] = nil
        }
    }

    // MARK: Rubble

    private func syncRubble(_ sim: MissionSimulation) {
        var alive = Set<Int>()
        for r in sim.hz.rubble {
            alive.insert(r.id)
            let n = rubble[r.id] ?? {
                let s = SKSpriteNode(texture: Art.rubble(), size: CGSize(width: 76, height: 29))
                s.anchorPoint = CGPoint(x: 0.5, y: 0)
                s.position = CGPoint(x: r.x, y: r.y - 2)
                s.zPosition = 3
                s.xScale = r.id % 2 == 0 ? 1 : -1
                if r.kind == "lavaBomb" { s.color = SKColor(red: 0.35, green: 0.1, blue: 0.05, alpha: 1); s.colorBlendFactor = 0.7 }
                addChild(s)
                rubble[r.id] = s
                return s
            }()
            n.alpha = CGFloat(min(1, max(0.15, (r.until - sim.time) / 3)))
        }
        for (id, n) in rubble where !alive.contains(id) { n.removeFromParent(); rubble[id] = nil }
    }

    // MARK: Lava and avalanches

    private func syncFlows(_ sim: MissionSimulation, dt: Double, camX: CGFloat) {
        for (i, f) in mission.flowList.enumerated() {
            let shape = flowShapes[i], glow = flowGlow[i]
            guard let span = sim.hz.flows[i].span else { shape.isHidden = true; glow.isHidden = true; continue }
            let lava = f.kind == "lava"
            let lo = max(span.lo, Double(camX) - 900), hi = min(span.hi, Double(camX) + 900)
            guard hi > lo else { shape.isHidden = true; glow.isHidden = true; continue }
            shape.isHidden = false; glow.isHidden = false
            let surge = f.kind == "surge"
            let thick = lava ? 12.0 : (surge ? f.clearance - 6 : 34.0)
            let wobble = lava ? 3.0 : 6.0
            let step = 14.0
            let top = CGMutablePath(), halo = CGMutablePath()
            var x = lo
            var first = true
            var pts: [CGPoint] = []
            while x <= hi {
                let y = mission.surfaceHeight(at: x) + thick + wobble * sin(x * 0.07 + clock * 2.2)
                pts.append(CGPoint(x: x, y: y))
                x += step
            }
            pts.append(CGPoint(x: hi, y: mission.surfaceHeight(at: hi) + thick))
            for p in pts { if first { top.move(to: p); first = false } else { top.addLine(to: p) } }
            for p in pts.reversed() { top.addLine(to: CGPoint(x: p.x, y: mission.surfaceHeight(at: Double(p.x)) - 3)) }
            top.closeSubpath()
            shape.path = top
            first = true
            for p in pts { let q = CGPoint(x: p.x, y: p.y + (lava ? 26 : 22)); if first { halo.move(to: q); first = false } else { halo.addLine(to: q) } }
            for p in pts.reversed() { halo.addLine(to: CGPoint(x: p.x, y: mission.surfaceHeight(at: Double(p.x)) - 3)) }
            halo.closeSubpath()
            glow.path = halo

            flowPuff[i] -= dt
            if flowPuff[i] <= 0 {
                flowPuff[i] = lava ? 0.12 : 0.04
                let fx = lava ? Double.random(in: lo...hi) : span.hi - (span.hi - span.lo) * Double.random(in: 0...0.25)
                let fxClamped = min(max(fx, lo), hi)
                let gy = mission.surfaceHeight(at: fxClamped) + thick
                let puff = SKSpriteNode(texture: Art.puff(), size: CGSize(width: lava ? 40 : 70, height: lava ? 40 : 70))
                if surge { puff.color = SKColor(red: 0.8, green: 0.9, blue: 0.92, alpha: 1); puff.colorBlendFactor = 1 }
                if lava { puff.color = SKColor(red: 0.2, green: 0.17, blue: 0.16, alpha: 1); puff.colorBlendFactor = 1 }
                puff.alpha = lava ? 0.35 : 0.6
                puff.position = CGPoint(x: fxClamped, y: gy + 6)
                addChild(puff)
                puff.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -20...20) + (lava ? 0 : (f.x1 >= f.x0 ? 60 : -60)), y: lava ? 90 : 60, duration: 1.6),
                                            .fadeOut(withDuration: 1.6), .scale(to: 2.2, duration: 1.6)]), .removeFromParent()]))
            }
        }
    }

    // MARK: One-shot effects

    func handle(_ e: SimEvent, sim: MissionSimulation) {
        switch e {
        case .impact(let kind, let x, _):
            let y = floor(at: x, sim)
            let lava = kind == "lavaBomb"
            for _ in 0..<(lava ? 8 : 12) {
                let p = SKSpriteNode(texture: Art.puff())
                let s = CGFloat.random(in: 26...70)
                p.size = CGSize(width: s, height: s)
                if lava { p.color = SKColor(red: 1, green: 0.5, blue: 0.12, alpha: 1); p.colorBlendFactor = 0.9; p.blendMode = .add }
                else { p.color = SKColor(red: 0.7, green: 0.64, blue: 0.55, alpha: 1); p.colorBlendFactor = 0.85 }
                p.alpha = lava ? 0.8 : 0.7
                p.position = CGPoint(x: x + CGFloat.random(in: -18...18), y: y + 6)
                p.zPosition = 13
                addChild(p)
                let d = CGFloat.random(in: -80...80)
                p.run(.sequence([.group([.moveBy(x: d, y: CGFloat.random(in: 20...90), duration: lava ? 0.7 : 2.4),
                                         .fadeOut(withDuration: lava ? 0.7 : 2.4), .scale(to: lava ? 0.6 : 2.6, duration: lava ? 0.7 : 2.4)]),
                                 .removeFromParent()]))
            }
        case .lightning(let x, _):
            let y = floor(at: x, sim)
            for _ in 0..<6 {
                let p = SKSpriteNode(texture: Art.puff(), size: CGSize(width: 30, height: 30))
                p.blendMode = .add; p.alpha = 0.9
                p.position = CGPoint(x: x + CGFloat.random(in: -24...24), y: y + 6)
                p.zPosition = 14
                addChild(p)
                p.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -60...60), y: CGFloat.random(in: 10...60), duration: 0.5), .fadeOut(withDuration: 0.5)]), .removeFromParent()]))
            }
        default: break
        }
    }
}
