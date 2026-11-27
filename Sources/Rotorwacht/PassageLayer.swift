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
    private lazy var signalTextures: [ShutterLight: SKTexture?] = [
        .green: Render.texture("passages", "signal-green"), .amber: Render.texture("passages", "signal-amber"),
        .red: Render.texture("passages", "signal-red")]

    private struct DoorNodes {
        let door = SKSpriteNode(), bar = SKSpriteNode(), housing = SKSpriteNode()
        let posts = [SKSpriteNode(), SKSpriteNode()], signals = [SKSpriteNode(), SKSpriteNode()]
        let beacons = [SKSpriteNode(), SKSpriteNode()], flashes = [SKSpriteNode(), SKSpriteNode()]
        let glows = [SKSpriteNode(), SKSpriteNode()], floorGlow = SKSpriteNode()
    }

    /// Sizes of the pictures in world units (see art/passages.py). The hit box of a door is `Shutter.halfThickness`;
    /// the picture is only a little wider than that, the rest of the frame stands behind the helicopter.
    private static let doorPictureHeight: CGFloat = 200
    private static let doorWidth: CGFloat = 22
    private static let barSize = CGSize(width: 38, height: 16)
    private static let housingSize = CGSize(width: 66, height: 26)
    private static let postOffset: CGFloat = 24
    private static let signalOffset: CGFloat = 44

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
                mass = SKSpriteNode(texture: t, size: CGSize(width: w + (p.isTunnel ? 48 : 32), height: h))
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
                addTunnel(p, floor: floor, roof: roof)
            } else {
                interiors.append(nil)
                ceilingGlow.append([])
                // Piers at both ends, behind the helicopter, so the bridge does not hang in the air.
                for x in [p.x0 - 6, p.x1 + 6] {
                    let size = CGSize(width: 44, height: roof + 40)
                    let pier: SKSpriteNode
                    if let t = Render.texture("passages", "pier-\(mission.id)-\(p.id)") {
                        pier = SKSpriteNode(texture: t, size: size)
                    } else {
                        pier = SKSpriteNode(color: SKColor(red: 0.52, green: 0.5, blue: 0.46, alpha: 1), size: CGSize(width: 26, height: roof + 40))
                    }
                    pier.anchorPoint = CGPoint(x: 0.5, y: 1)
                    pier.position = CGPoint(x: x, y: Double(roof))
                    pier.zPosition = -1
                    addChild(pier)
                }
            }

            doors.append(p.shutterList.map { addShutter($0, floor: floor, roof: roof) })
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

    /// The inside of a tunnel: the mountain behind it, the lit back wall, the dark film over the helicopter, the portals.
    private func addTunnel(_ p: Passage, floor: CGFloat, roof: CGFloat) {
        let cx = CGFloat(p.x0 + p.x1) / 2, w = CGFloat(p.x1 - p.x0), gap = roof - floor
        if let t = Render.texture("passages", "flank-\(mission.id)-\(p.id)") {
            // Behind the terrain (absolute z -25), so the ground hides its foot and the tunnel sits in the landscape.
            let flank = SKSpriteNode(texture: t, size: CGSize(width: w + 600, height: CGFloat(mission.world.ceiling) + 40 - (floor - 140)))
            flank.anchorPoint = CGPoint(x: 0.5, y: 0)
            flank.position = CGPoint(x: cx, y: floor - 140)
            flank.zPosition = -35
            addChild(flank)
        }
        let dark = SKSpriteNode(color: SKColor(red: 0.02, green: 0.02, blue: 0.03, alpha: 0.3), size: CGSize(width: w, height: gap))
        dark.anchorPoint = CGPoint(x: 0.5, y: 0)
        dark.position = CGPoint(x: cx, y: floor)
        dark.zPosition = 0.4
        addChild(dark)
        interiors.append(dark)
        let back: SKSpriteNode
        if let t = Render.texture("passages", "interior-\(mission.id)-\(p.id)") {
            back = SKSpriteNode(texture: t, size: CGSize(width: w, height: gap))
        } else {
            back = SKSpriteNode(color: SKColor(white: 0.18, alpha: 1), size: CGSize(width: w, height: gap))
        }
        back.anchorPoint = CGPoint(x: 0.5, y: 0)
        back.position = CGPoint(x: cx, y: floor)
        back.zPosition = -3.5
        addChild(back)
        for x in [p.x0, p.x1] {
            guard let t = Render.texture("passages", "jamb-\(mission.id)-\(p.id)") else { break }
            let jamb = SKSpriteNode(texture: t, size: CGSize(width: 26, height: gap))
            jamb.anchorPoint = CGPoint(x: 0.5, y: 0)
            jamb.position = CGPoint(x: x, y: Double(floor))
            jamb.zPosition = -3.4
            addChild(jamb)
        }
        var lights: [SKSpriteNode] = []
        var x = p.x0 + 60
        while x < p.x1 - 20 {
            let g = SKSpriteNode(texture: Art.beaconGlow(), size: CGSize(width: 130, height: 60))
            g.position = CGPoint(x: x, y: Double(roof) - 14)
            g.zPosition = 0.6
            g.blendMode = .add
            g.alpha = 0.3
            addChild(g)
            lights.append(g)
            x += 80
        }
        ceilingGlow.append(lights)
    }

    /// A roll-up door with its frame, two traffic lights, two warning beacons and the glow that shows it in the dark.
    private func addShutter(_ s: Shutter, floor: CGFloat, roof: CGFloat) -> DoorNodes {
        let d = DoorNodes()
        let x = CGFloat(s.x)
        func sprite(_ n: SKSpriteNode, _ name: String?, _ size: CGSize, _ pos: CGPoint, _ z: CGFloat, anchorY: CGFloat = 0.5) {
            if let name { n.texture = Render.texture("passages", name) }
            n.size = size
            n.anchorPoint = CGPoint(x: 0.5, y: anchorY)
            n.position = pos
            n.zPosition = z
            addChild(n)
        }
        func glow(_ n: SKSpriteNode, _ size: CGSize, _ pos: CGPoint, _ z: CGFloat) {
            sprite(n, nil, size, pos, z)
            n.texture = Art.beaconGlow()
            n.blendMode = .add
            n.colorBlendFactor = 1
        }
        for (i, side) in [CGFloat(-1), 1].enumerated() {
            // Posts and signals stand behind the helicopter (z below its 10), only the door itself is in front.
            sprite(d.posts[i], "shutter-post", CGSize(width: 10, height: roof - floor), CGPoint(x: x + side * Self.postOffset, y: floor), -0.3, anchorY: 0)
            if let t = d.posts[i].texture {
                d.posts[i].texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: min(1, (roof - floor) / Self.doorPictureHeight)), in: t)
            }
            let signal = CGPoint(x: x + side * Self.signalOffset, y: roof - Self.housingSize.height - 30)
            sprite(d.signals[i], "signal-green", CGSize(width: 20, height: 48), signal, -0.25)
            glow(d.glows[i], CGSize(width: 90, height: 90), signal, 0.32)
            let beacon = CGPoint(x: x + side * 25, y: roof - Self.housingSize.height - 4)
            sprite(d.beacons[i], "beacon", CGSize(width: 12, height: 12), beacon, 0.28)
            d.beacons[i].yScale = -1   // hangs under the housing
            glow(d.flashes[i], CGSize(width: 110, height: 110), beacon, 0.33)
            d.flashes[i].color = SKColor(red: 1, green: 0.66, blue: 0.1, alpha: 1)
        }
        sprite(d.door, nil, CGSize(width: Self.doorWidth, height: 1), CGPoint(x: x, y: roof), 0.2, anchorY: 1)
        sprite(d.bar, "shutter-bar", Self.barSize, CGPoint(x: x, y: roof), 0.22, anchorY: 0)
        sprite(d.housing, "shutter-housing", Self.housingSize, CGPoint(x: x, y: roof), 0.25, anchorY: 1)
        glow(d.floorGlow, CGSize(width: 130, height: 34), CGPoint(x: x, y: floor + 6), 0.31)
        return d
    }

    private static let roofShadow: SKTexture = Art.texture(CGSize(width: 8, height: 46)) { ctx in
        Art.fillVertical(ctx, CGRect(x: 0, y: 0, width: 8, height: 46), [(0, 0x000000, 0.5), (1, 0x000000, 0)])
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
                let barHeight = Self.barSize.height
                let showDoor = full > barHeight + 1
                n.door.isHidden = !showDoor
                if showDoor {
                    let length = full - barHeight
                    if let t = Render.texture("passages", "shutter-door") {
                        // The lower part of the curtain: it comes out of the housing.
                        n.door.texture = SKTexture(rect: CGRect(x: 0, y: 0, width: 1, height: min(1, length / Self.doorPictureHeight)), in: t)
                    } else {
                        n.door.color = SKColor(red: 0.95, green: 0.76, blue: 0.2, alpha: 1)
                    }
                    n.door.size = CGSize(width: Self.doorWidth, height: length)
                }
                // Fully open, the bar stays just under the housing so the door can be seen from afar.
                n.bar.position = CGPoint(x: s.x, y: Double(min(bottom, roof - Self.housingSize.height - barHeight)))
                if showDoor { n.bar.position.y = bottom }
                let light = sim.shutterLight(passage: pi, shutter: si)
                let blink = Int(clock * 5) % 2 == 0
                let on: Bool = light == .amber ? blink : true
                let color = light == .green ? SKColor(red: 0.2, green: 1, blue: 0.45, alpha: 1)
                    : (light == .amber ? SKColor(red: 1, green: 0.7, blue: 0.15, alpha: 1) : SKColor(red: 1, green: 0.2, blue: 0.14, alpha: 1))
                // Warning beacons turn from the amber phase on and as long as the curtain moves.
                let closing = light == .amber || (open > 0.001 && open < 0.999)
                for i in 0..<2 {
                    n.signals[i].texture = signalTextures[light] ?? nil
                    n.signals[i].alpha = on ? 1 : 0.7
                    // The glow sits on the lit lamp: red on top, green at the bottom.
                    let lampY: CGFloat = light == .red ? 14 : (light == .amber ? 0 : -14)
                    n.glows[i].position.y = n.signals[i].position.y + lampY
                    n.glows[i].color = color
                    n.glows[i].alpha = on ? 0.85 : 0.15
                    let turn = CGFloat(max(0, sin(clock * 13 + Double(i) * .pi)))
                    n.flashes[i].alpha = closing ? 0.25 + 0.75 * turn : 0
                }
                n.floorGlow.color = color
                n.floorGlow.alpha = light == .green ? 0.4 : (on ? 0.8 : 0.2)
            }
        }
        // The searchlight of the helicopter lights its surroundings inside.
        let target: CGFloat = inside ? 1 : 0
        spot.alpha += (target * 0.6 - spot.alpha) * CGFloat(min(1, dt * 6))
        spot.position = CGPoint(x: h.x + CGFloat(h.heading) * 70, y: h.y + 30)
    }

    /// Door and ceiling events for sound and hints are handled by the scene.
}
