import SpriteKit
import RotorwachtCore

/// Draws the passages (underpasses and tunnels) in world space: the solid above the roof (rendered in Blender),
/// the dark inside of a tunnel with the helicopter's searchlight, and the roll-up doors with their signal lamps.
/// Rules live in RotorwachtCore (`Passages.swift`).
final class PassageLayer: SKNode {
    private let mission: Mission
    private var interiors: [SKSpriteNode?] = []
    private var shades: [SKSpriteNode?] = []
    private var doors: [[DoorNodes]] = []
    private var ceilingGlow: [[SKSpriteNode]] = []
    private let spot = SKSpriteNode()
    private var clock = 0.0
    private lazy var lampTextures: [ShutterLight: SKTexture?] = [
        .green: Render.texture("passages", "lamp-green"), .amber: Render.texture("passages", "lamp-amber"),
        .red: Render.texture("passages", "lamp-red")]

    private struct DoorNodes {
        let door = SKSpriteNode(), bar = SKSpriteNode(), housing = SKSpriteNode()
        let lampL = SKSpriteNode(), lampR = SKSpriteNode(), glow = SKSpriteNode()
    }

    /// Height of the full door picture in world units (see art/passages.py).
    private static let doorPictureHeight: CGFloat = 200
    private static let barHeight: CGFloat = 8
    private static let housingHeight: CGFloat = 14

    init(mission: Mission) {
        self.mission = mission
        super.init()
        zPosition = 10
        for p in mission.passageList {
            let floor = CGFloat(p.floorRef(in: mission)), roof = CGFloat(p.roof)
            let cx = CGFloat(p.x0 + p.x1) / 2, w = CGFloat(p.x1 - p.x0)
            // The solid above the roof, up to the flight ceiling.
            let h = CGFloat(mission.world.ceiling) - roof + 12
            let mass: SKSpriteNode
            if let t = Render.texture("passages", "mass-\(mission.id)-\(p.id)") {
                mass = SKSpriteNode(texture: t, size: CGSize(width: w + 32, height: h))
            } else {
                mass = SKSpriteNode(color: p.isTunnel ? SKColor(white: 0.22, alpha: 1) : SKColor(white: 0.6, alpha: 1), size: CGSize(width: w, height: h))
            }
            mass.anchorPoint = CGPoint(x: 0.5, y: 0)
            mass.position = CGPoint(x: cx, y: roof)
            mass.zPosition = 0.5
            addChild(mass)

            // Shadow under the roof (both kinds).
            let sh = SKSpriteNode(texture: Self.roofShadow, size: CGSize(width: w, height: 46))
            sh.anchorPoint = CGPoint(x: 0.5, y: 1)
            sh.position = CGPoint(x: cx, y: roof)
            sh.zPosition = 0.45
            addChild(sh)
            shades.append(sh)

            if p.isTunnel {
                let dark = SKSpriteNode(color: SKColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.62), size: CGSize(width: w, height: roof - floor))
                dark.anchorPoint = CGPoint(x: 0.5, y: 0)
                dark.position = CGPoint(x: cx, y: floor)
                dark.zPosition = 0.4
                addChild(dark)
                interiors.append(dark)
                // Back wall behind the helicopter: ribs and lamps, so the tunnel does not look empty.
                let back = SKSpriteNode(texture: Self.tunnelWall(width: w, height: roof - floor), size: CGSize(width: w, height: roof - floor))
                back.anchorPoint = CGPoint(x: 0.5, y: 0)
                back.position = CGPoint(x: cx, y: floor)
                back.zPosition = -3.5
                addChild(back)
                var lights: [SKSpriteNode] = []
                var x = p.x0 + 60
                while x < p.x1 - 20 {
                    let g = SKSpriteNode(texture: Art.beaconGlow(), size: CGSize(width: 130, height: 60))
                    g.position = CGPoint(x: x, y: Double(roof) - 14)
                    g.zPosition = 0.6
                    g.blendMode = .add
                    g.alpha = 0.55
                    addChild(g)
                    lights.append(g)
                    x += 120
                }
                ceilingGlow.append(lights)
            } else {
                interiors.append(nil)
                ceilingGlow.append([])
                // Piers at both ends, behind the helicopter, so the viaduct does not hang in the air.
                for side in [-1.0, 1.0] {
                    let pier = SKSpriteNode(color: SKColor(red: 0.52, green: 0.5, blue: 0.46, alpha: 1), size: CGSize(width: 26, height: roof + 40))
                    pier.anchorPoint = CGPoint(x: 0.5, y: 1)
                    pier.position = CGPoint(x: side < 0 ? p.x0 - 6 : p.x1 + 6, y: Double(roof))
                    pier.zPosition = -1
                    addChild(pier)
                    let shade = SKSpriteNode(color: SKColor(white: 0, alpha: 0.18), size: CGSize(width: 9, height: roof + 40))
                    shade.anchorPoint = CGPoint(x: 0.5, y: 1)
                    shade.position = CGPoint(x: pier.position.x + (side < 0 ? 8 : -8), y: Double(roof))
                    shade.zPosition = -0.9
                    addChild(shade)
                }
            }

            var list: [DoorNodes] = []
            for s in p.shutterList {
                let d = DoorNodes()
                d.door.anchorPoint = CGPoint(x: 0.5, y: 1)
                d.door.zPosition = 0.2
                d.bar.texture = Render.texture("passages", "shutter-bar")
                d.bar.size = CGSize(width: 24, height: Self.barHeight)
                d.bar.anchorPoint = CGPoint(x: 0.5, y: 0)
                d.bar.zPosition = 0.21
                d.housing.texture = Render.texture("passages", "shutter-housing")
                d.housing.size = CGSize(width: 38, height: Self.housingHeight)
                d.housing.anchorPoint = CGPoint(x: 0.5, y: 1)
                d.housing.position = CGPoint(x: s.x, y: Double(roof))
                d.housing.zPosition = 0.25
                for lamp in [d.lampL, d.lampR] {
                    lamp.size = CGSize(width: 26, height: 26)
                    lamp.zPosition = 0.3
                }
                d.lampL.position = CGPoint(x: s.x - 30, y: Double(roof) - 30)
                d.lampR.position = CGPoint(x: s.x + 30, y: Double(roof) - 30)
                d.glow.texture = Art.beaconGlow()
                d.glow.size = CGSize(width: 150, height: 150)
                d.glow.blendMode = .add
                d.glow.colorBlendFactor = 1
                d.glow.zPosition = 0.35
                d.glow.position = CGPoint(x: s.x, y: Double(roof) - 30)
                for n in [d.door, d.bar, d.housing, d.lampL, d.lampR, d.glow] { addChild(n) }
                list.append(d)
            }
            doors.append(list)
        }
        spot.texture = Art.beaconGlow()
        spot.blendMode = .add
        spot.size = CGSize(width: 420, height: 230)
        spot.color = SKColor(red: 1, green: 0.93, blue: 0.75, alpha: 1)
        spot.colorBlendFactor = 1
        spot.zPosition = 0.6
        spot.alpha = 0
        addChild(spot)
    }
    required init?(coder: NSCoder) { fatalError() }

    private static let roofShadow: SKTexture = Art.texture(CGSize(width: 8, height: 46)) { ctx in
        Art.fillVertical(ctx, CGRect(x: 0, y: 0, width: 8, height: 46), [(0, 0x000000, 0.5), (1, 0x000000, 0)])
    }

    private static func tunnelWall(width: CGFloat, height: CGFloat) -> SKTexture {
        Art.texture(CGSize(width: width, height: height)) { ctx in
            Art.fillVertical(ctx, CGRect(x: 0, y: 0, width: width, height: height), [(0, 0x4b4742, 1), (1, 0x2c2a27, 1)])
            ctx.setFillColor(Art.c(0x211f1d, 0.9))
            var x: CGFloat = 20
            while x < width { ctx.fill(CGRect(x: x, y: 0, width: 10, height: height)); x += 60 }
            ctx.setFillColor(Art.c(0x1b1a18, 1))
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: 6))
            ctx.setFillColor(Art.c(0xe9c85a, 0.9))
            ctx.fill(CGRect(x: 0, y: 12, width: width, height: 3))
        }
    }

    /// Whether the helicopter is inside a tunnel (its middle between both ends).
    func sync(sim: MissionSimulation, dt: Double) {
        clock += dt
        let h = sim.heli
        var inside = false
        for (pi, p) in mission.passageList.enumerated() {
            let floor = CGFloat(sim.passageFloor(pi)), roof = CGFloat(p.roof)
            if p.isTunnel, h.x > p.x0 - 60, h.x < p.x1 + 60 { inside = true }
            // The back wall and dark film follow a rising flood too.
            if let dark = interiors[pi] { dark.position.y = floor; dark.size.height = max(1, roof - floor) }
            for (i, light) in ceilingGlow[pi].enumerated() { light.alpha = 0.5 + 0.1 * CGFloat(sin(clock * 9 + Double(i) * 2.3)) }
            for (si, s) in p.shutterList.enumerated() {
                let n = doors[pi][si]
                let open = sim.shutterOpenness(passage: pi, shutter: si)
                let bottom = floor + CGFloat(min(s.gap ?? Double(roof - floor), Double(roof - floor))) * CGFloat(open)
                let full = roof - bottom
                let showDoor = full > Self.barHeight + 1
                n.door.isHidden = !showDoor
                n.bar.isHidden = !showDoor
                if showDoor, let t = Render.texture("passages", "shutter-door") {
                    let vis = min(Self.doorPictureHeight, full - Self.barHeight)
                    n.door.texture = SKTexture(rect: CGRect(x: 0, y: 1 - vis / Self.doorPictureHeight, width: 1, height: vis / Self.doorPictureHeight), in: t)
                    n.door.size = CGSize(width: 16, height: full - Self.barHeight)
                    n.door.position = CGPoint(x: s.x, y: Double(roof))
                    // Beyond the picture height the slats simply continue: stretch is fine, the door is hidden in the housing.
                } else if showDoor {
                    n.door.color = SKColor(red: 0.55, green: 0.6, blue: 0.64, alpha: 1)
                    n.door.size = CGSize(width: 16, height: full - Self.barHeight)
                    n.door.position = CGPoint(x: s.x, y: Double(roof))
                }
                n.bar.position = CGPoint(x: s.x, y: Double(bottom))
                let light = sim.shutterLight(passage: pi, shutter: si)
                let on: Bool = light == .amber ? Int(clock * 5) % 2 == 0 : true
                for lamp in [n.lampL, n.lampR] {
                    lamp.texture = lampTextures[light] ?? nil
                    lamp.isHidden = false
                    lamp.alpha = on ? 1 : 0.35
                }
                n.glow.color = light == .green ? SKColor(red: 0.2, green: 1, blue: 0.4, alpha: 1)
                    : (light == .amber ? SKColor(red: 1, green: 0.7, blue: 0.2, alpha: 1) : SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 1))
                n.glow.alpha = (on ? 0.7 : 0.15) * (light == .green ? 0.5 : 1)
            }
        }
        // The searchlight of the helicopter lights its surroundings inside.
        let target: CGFloat = inside ? 1 : 0
        spot.alpha += (target * 0.6 - spot.alpha) * CGFloat(min(1, dt * 6))
        spot.position = CGPoint(x: h.x + CGFloat(h.heading) * 70, y: h.y + 30)
    }

    /// Door and ceiling events for sound and hints are handled by the scene.
}
