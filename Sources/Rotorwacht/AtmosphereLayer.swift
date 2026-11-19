import SpriteKit
import RotorwachtCore

/// Weather and light in front of the picture (child of the camera): rain, snow, ash, dust, night with a spotlight cone,
/// lightning flashes. Only the look; ash and night have no effect on the rules.
final class AtmosphereLayer: SKNode {
    private let mission: Mission
    private var precip: SKEmitterNode?
    private let ashOverlay = SKSpriteNode()
    private let dim = SKSpriteNode()
    private let darkness = SKSpriteNode()
    private let flashNode = SKSpriteNode()
    private var flashLevel: CGFloat = 0
    private var ashSmooth: CGFloat = 0
    let isNight: Bool

    init(mission: Mission, size: CGSize) {
        self.mission = mission
        isNight = mission.isNight
        super.init()
        let a = mission.atmosphere
        switch a?.precipitation {
        case "rain":
            let storm = !mission.stormList.isEmpty
            let e = emitter(texture: Art.raindrop(), rate: storm ? 480 : 260, life: 1.1, speed: 820, size: CGSize(width: 3, height: 22), alpha: storm ? 0.34 : 0.28)
            e.emissionAngle = CGFloat.pi * 1.5 + (storm ? 0.28 : 0.12)
            e.particleRotation = storm ? 0.28 : 0.12
            precip = e
        case "snow":
            let e = emitter(texture: Art.fleck(), rate: 170, life: 5, speed: 95, size: CGSize(width: 5, height: 5), alpha: 0.85)
            e.particleSpeedRange = 40
            e.emissionAngle = CGFloat.pi * 1.5
            precip = e
        case "ash":
            let e = emitter(texture: Art.fleck(), rate: 130, life: 5.5, speed: 70, size: CGSize(width: 6, height: 6), alpha: 0.75)
            e.particleColor = SKColor(red: 0.20, green: 0.17, blue: 0.15, alpha: 1)
            e.particleColorBlendFactor = 1
            e.particleSpeedRange = 30
            e.emissionAngle = CGFloat.pi * 1.5
            precip = e
        default: break
        }
        if let p = precip { addChild(p); p.advanceSimulationTime(4) }

        let tint: SKColor
        switch a?.sky {
        case "ash": tint = SKColor(red: 0.30, green: 0.22, blue: 0.18, alpha: 1)
        case "dust": tint = SKColor(red: 0.62, green: 0.52, blue: 0.40, alpha: 1)
        case "alpine": tint = SKColor(red: 0.86, green: 0.92, blue: 0.97, alpha: 1)
        case "night": tint = SKColor(red: 0.04, green: 0.08, blue: 0.14, alpha: 1)
        default: tint = SKColor(red: 0.10, green: 0.16, blue: 0.20, alpha: 1)
        }
        dim.color = tint; dim.size = size
        dim.alpha = a?.sky == "dust" ? 0.16 : (a?.sky == "alpine" ? 0.10 : 0.10)
        dim.zPosition = 29
        addChild(dim)

        ashOverlay.color = SKColor(red: 0.26, green: 0.20, blue: 0.17, alpha: 1)
        ashOverlay.size = size
        ashOverlay.alpha = 0
        ashOverlay.zPosition = 30.5
        addChild(ashOverlay)

        if isNight {
            darkness.texture = Art.nightCone()
            darkness.size = CGSize(width: 3200, height: 3200)
            darkness.zPosition = 25
            addChild(darkness)
        }
        flashNode.color = SKColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
        flashNode.size = size
        flashNode.alpha = 0
        flashNode.zPosition = 33
        addChild(flashNode)
    }
    required init?(coder: NSCoder) { fatalError() }

    private func emitter(texture: SKTexture, rate: CGFloat, life: CGFloat, speed: CGFloat, size: CGSize, alpha: CGFloat) -> SKEmitterNode {
        let e = SKEmitterNode()
        e.particleTexture = texture
        e.particleBirthRate = rate
        e.particleLifetime = life
        e.particlePositionRange = CGVector(dx: 1700, dy: 0)
        e.position = CGPoint(x: 0, y: 420)
        e.particleSpeed = speed
        e.particleSpeedRange = 120
        e.particleAlpha = alpha
        e.particleSize = size
        e.zPosition = 30
        return e
    }

    /// Lightning flash over the whole picture.
    func flash(_ strength: CGFloat = 0.8) { flashLevel = max(flashLevel, strength) }

    /// `heli` is the helicopter's position relative to the camera.
    func sync(sim: MissionSimulation, heli: CGPoint, dt: Double) {
        if let p = precip, mission.atmosphere?.precipitation != "rain" {
            p.xAcceleration = CGFloat(sim.wind) * 0.7
        }
        let target = CGFloat(sim.ash) * 0.68
        ashSmooth += (target - ashSmooth) * CGFloat(min(1, dt * 2.5))
        ashOverlay.alpha = ashSmooth
        if isNight {
            let h = sim.heli
            let f = CGFloat(h.facing)
            darkness.position = CGPoint(x: heli.x, y: heli.y + 30)
            darkness.zRotation = atan2(-(0.5 + (1 - abs(f)) * 3), f == 0 ? 0.001 : f)
        }
        flashLevel *= CGFloat(exp(-9 * dt))
        flashNode.alpha = flashLevel > 0.02 ? flashLevel * (Int(flashLevel * 40) % 3 == 0 ? 0.6 : 1) : 0
    }
}
