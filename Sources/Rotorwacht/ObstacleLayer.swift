import SpriteKit
import RotorwachtCore

/// Draws the obstacles (power lines, cranes, cable cars, wind turbines) in world space: Blender parts for pylons,
/// jibs, gondolas, towers and blades; wires and ropes as lines. Positions of moving parts come from the same
/// functions of time (`Obstacle.swing`, `gondola`, `bladeAngle`) that the hit test uses.
/// Rules live in RotorwachtCore (`Obstacles.swift`).
final class ObstacleLayer: SKNode {
    private let mission: Mission
    private var clock = 0.0
    private var cranes: [Int: CraneNodes] = [:]
    private var cars: [Int: GondolaNodes] = [:]
    private var mills: [Int: MillNodes] = [:]

    private struct CraneNodes { let jib: SKSpriteNode; let rope: SKShapeNode; let load: SKSpriteNode }
    private struct GondolaNodes { let cabin: SKSpriteNode }
    private struct MillNodes { let blades: [SKSpriteNode]; let hub: SKSpriteNode }

    private static let wireColor = SKColor(red: 0.16, green: 0.17, blue: 0.19, alpha: 1)
    private static let tileHeight: CGFloat = 32
    private static let jibPictureWidth: CGFloat = 240, jibPictureHeight: CGFloat = 72, jibAxis: CGFloat = 60, jibLevel: CGFloat = 16, jibLength: CGFloat = 160

    init(mission: Mission) {
        self.mission = mission
        super.init()
        zPosition = 8
        for (i, o) in mission.obstacleList.enumerated() {
            switch o.kind {
            case "powerline": buildLine(o, powerline: true)
            case "cablecar": buildLine(o, powerline: false); buildGondola(i, o)
            case "crane": buildCrane(i, o)
            case "windmill": buildMill(i, o)
            default: break
            }
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Building

    private func sprite(_ name: String, size: CGSize, anchor: CGPoint, fallback: SKColor) -> SKSpriteNode {
        let n: SKSpriteNode
        if let t = Render.texture("obstacles", name) { n = SKSpriteNode(texture: t, size: size) }
        else { n = SKSpriteNode(color: fallback, size: size) }
        n.anchorPoint = anchor
        return n
    }

    /// A lattice shaft of stacked tiles from `base` up to `top`, centred at x.
    private func shaft(tile: String, width: CGFloat, x: CGFloat, base: CGFloat, top: CGFloat, color: SKColor, z: CGFloat) {
        let h = max(1, top - base)
        let n = max(1, Int((h / Self.tileHeight).rounded()))
        let step = h / CGFloat(n)
        for k in 0..<n {
            let t = sprite(tile, size: CGSize(width: width, height: step + 0.5), anchor: CGPoint(x: 0.5, y: 0), fallback: color)
            t.position = CGPoint(x: x, y: base + CGFloat(k) * step)
            t.zPosition = z
            addChild(t)
        }
    }

    private func wire(_ points: [CGPoint], width: CGFloat = 2, z: CGFloat = 0.5) {
        let p = CGMutablePath()
        p.addLines(between: points)
        let s = SKShapeNode(path: p)
        s.strokeColor = Self.wireColor
        s.lineWidth = width
        s.lineCap = .round
        s.zPosition = z
        addChild(s)
    }

    private func buildLine(_ o: Obstacle, powerline: Bool) {
        let (a, b) = o.anchors(in: mission)
        let drops = powerline ? Obstacle.wireDrops : [0]
        for d in drops {
            let pts = (0...24).map { i -> CGPoint in
                let u = Double(i) / 24
                return CGPoint(x: a.x + (b.x - a.x) * u, y: o.wireY(in: mission, u: u, drop: d))
            }
            wire(pts, width: powerline ? 2 : 2.5)
        }
        for (p, x) in [(a, o.x), (b, o.x1 ?? o.x)] {
            let g = CGFloat(mission.groundHeight(at: x))
            if powerline {
                // Head: the top arm carries the first wire, the lower one the second (see art/obstacles.py).
                shaft(tile: "tower-tile", width: 36, x: CGFloat(x), base: g - 6, top: CGFloat(p.y) - 80 + 6, color: SKColor(white: 0.5, alpha: 1), z: 0)
                let head = sprite("pylon-head", size: CGSize(width: 80, height: 96), anchor: CGPoint(x: 0.5, y: 0), fallback: SKColor(white: 0.5, alpha: 1))
                head.position = CGPoint(x: CGFloat(x), y: CGFloat(p.y) - 80)
                head.zPosition = 0.2
                addChild(head)
            } else {
                shaft(tile: "tower-tile", width: 28, x: CGFloat(x), base: g - 6, top: CGFloat(p.y) - 44 + 6, color: SKColor(white: 0.5, alpha: 1), z: 0)
                let head = sprite("cable-head", size: CGSize(width: 56, height: 48), anchor: CGPoint(x: 0.5, y: 0), fallback: SKColor(red: 0.78, green: 0.31, blue: 0.23, alpha: 1))
                head.position = CGPoint(x: CGFloat(x), y: CGFloat(p.y) - 44)
                head.zPosition = 0.2
                addChild(head)
            }
        }
    }

    private func buildGondola(_ i: Int, _ o: Obstacle) {
        let cabin = sprite("gondola", size: CGSize(width: 60, height: 72), anchor: CGPoint(x: 0.5, y: 1), fallback: SKColor(red: 0.78, green: 0.31, blue: 0.23, alpha: 1))
        cabin.zPosition = 0.4
        addChild(cabin)
        cars[i] = GondolaNodes(cabin: cabin)
    }

    private func buildCrane(_ i: Int, _ o: Obstacle) {
        let g = CGFloat(mission.groundHeight(at: o.x)), top = g + CGFloat(o.height)
        shaft(tile: "crane-tile", width: 36, x: CGFloat(o.x), base: g - 6, top: top, color: SKColor(red: 0.91, green: 0.78, blue: 0.35, alpha: 1), z: 0)
        let jib = sprite("crane-jib", size: CGSize(width: Self.jibPictureWidth, height: Self.jibPictureHeight),
                         anchor: CGPoint(x: Self.jibAxis / Self.jibPictureWidth, y: Self.jibLevel / Self.jibPictureHeight),
                         fallback: SKColor(red: 0.91, green: 0.78, blue: 0.35, alpha: 1))
        jib.position = CGPoint(x: CGFloat(o.x), y: top)
        jib.zPosition = 0.3
        addChild(jib)
        let rope = SKShapeNode()
        rope.strokeColor = Self.wireColor
        rope.lineWidth = 1.5
        rope.zPosition = 0.35
        addChild(rope)
        let load = sprite("crane-hook", size: CGSize(width: 40, height: 40), anchor: CGPoint(x: 0.5, y: 1), fallback: SKColor(red: 0.66, green: 0.48, blue: 0.27, alpha: 1))
        load.zPosition = 0.36
        addChild(load)
        cranes[i] = CraneNodes(jib: jib, rope: rope, load: load)
    }

    private func buildMill(_ i: Int, _ o: Obstacle) {
        let g = CGFloat(mission.groundHeight(at: o.x)), hubY = g + CGFloat(o.height)
        let tower = sprite("windmill-tower", size: CGSize(width: 28, height: CGFloat(o.height) + 22), anchor: CGPoint(x: 0.5, y: 0), fallback: SKColor(white: 0.9, alpha: 1))
        tower.position = CGPoint(x: CGFloat(o.x), y: g - 4)
        tower.size.height += 4
        tower.zPosition = 0
        addChild(tower)
        let len = CGFloat(o.reach ?? 90)
        var blades: [SKSpriteNode] = []
        for _ in 0..<3 {
            let b = sprite("windmill-blade", size: CGSize(width: 22 * len / 128 * 1.1, height: len), anchor: CGPoint(x: 0.5, y: 0), fallback: SKColor(white: 0.95, alpha: 1))
            b.position = CGPoint(x: CGFloat(o.x), y: hubY)
            b.zPosition = 0.3
            addChild(b)
            blades.append(b)
        }
        let hub = sprite("windmill-hub", size: CGSize(width: 26, height: 26), anchor: CGPoint(x: 0.5, y: 0.5), fallback: SKColor(white: 0.85, alpha: 1))
        hub.position = CGPoint(x: CGFloat(o.x), y: hubY)
        hub.zPosition = 0.4
        addChild(hub)
        mills[i] = MillNodes(blades: blades, hub: hub)
    }

    // MARK: Frame

    func sync(sim: MissionSimulation, dt: Double) {
        clock = sim.time
        for (i, o) in mission.obstacleList.enumerated() {
            switch o.kind {
            case "crane":
                guard let n = cranes[i] else { continue }
                let g = CGFloat(mission.groundHeight(at: o.x)), top = g + CGFloat(o.height)
                let f = CGFloat(o.swing(at: clock))
                let reach = CGFloat(o.reach ?? 160)
                n.jib.xScale = (reach / Self.jibLength) * (abs(f) < 0.02 ? 0.02 : f)
                let tip = CGFloat(o.x) + reach * f
                let p = CGMutablePath()
                p.move(to: CGPoint(x: tip, y: top))
                p.addLine(to: CGPoint(x: tip, y: top - CGFloat(o.rope ?? 90)))
                n.rope.path = p
                n.load.position = CGPoint(x: tip, y: top - CGFloat(o.rope ?? 90))
            case "cablecar":
                guard let n = cars[i] else { continue }
                let c = o.gondolaCenter(at: clock, in: mission)
                n.cabin.position = CGPoint(x: c.x, y: c.y + Obstacle.gondolaDrop)
                n.cabin.zRotation = CGFloat(sin(clock * 1.3 + Double(i)) * 0.03)
            case "windmill":
                guard let n = mills[i] else { continue }
                let a = CGFloat(o.bladeAngle(at: clock))
                for (k, b) in n.blades.enumerated() {
                    b.zRotation = a + CGFloat(k) * 2 * .pi / 3 - .pi / 2
                }
            default: break
            }
        }
    }

    /// Sparks where the helicopter touched a wire or crashed into a solid part.
    func sparks(at p: CGPoint, big: Bool) {
        let e = SKEmitterNode()
        e.particleTexture = Art.fleck()
        e.particleBirthRate = 900
        e.numParticlesToEmit = big ? 70 : 36
        e.particleLifetime = 0.5
        e.particleLifetimeRange = 0.3
        e.particleSpeed = 220
        e.particleSpeedRange = 140
        e.emissionAngleRange = .pi * 2
        e.yAcceleration = -420
        e.particleSize = CGSize(width: 4, height: 4)
        e.particleColor = SKColor(red: 1, green: 0.78, blue: 0.35, alpha: 1)
        e.particleColorBlendFactor = 1
        e.particleBlendMode = .add
        e.particleAlphaSpeed = -1.6
        e.position = p
        e.zPosition = 5
        addChild(e)
        e.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }
}
