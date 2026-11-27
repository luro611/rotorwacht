import SpriteKit
import RotorwachtCore

/// Weather and light in front of the picture (child of the camera): rain, snow, ash, dust, night with a spotlight cone,
/// lightning flashes, and the weather schedule of the mission (fog banks with a clear patch around the helicopter,
/// the sky darkening before a thunderstorm, the windsock with its forecast). Only the look; ash, fog and night have
/// no effect on the rules.
final class AtmosphereLayer: SKNode {
    private let mission: Mission
    private var precip: SKEmitterNode?
    private let ashOverlay = SKSpriteNode()
    private let dim = SKSpriteNode()
    private let darkness = SKSpriteNode()
    private let flashNode = SKSpriteNode()
    private var flashLevel: CGFloat = 0
    private var ashSmooth: CGFloat = 0
    private let fog = SKSpriteNode()
    private let haze = SKSpriteNode()
    private let stormDim = SKSpriteNode()
    private let sock = WindSock()
    private var fogSmooth: CGFloat = 0
    /// Driven snow or sand while a whiteout or sandstorm is on.
    private let drift = SKEmitterNode()
    private var stormSmooth: CGFloat = 0
    private let viewSize: CGSize
    let isNight: Bool

    /// `weatherOnly`: the Einsatz has no `atmosphere` block, only a weather schedule; the scene keeps its own rain and dimming then.
    init(mission: Mission, size: CGSize, weatherOnly: Bool = false) {
        self.mission = mission
        viewSize = size
        isNight = mission.isNight
        super.init()
        buildWeather(size: size)
        if weatherOnly {
            flashNode.color = SKColor(red: 0.85, green: 0.9, blue: 1, alpha: 1)
            flashNode.size = size
            flashNode.alpha = 0
            flashNode.zPosition = 33
            addChild(flashNode)
            return
        }
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

    private func buildWeather(size: CGSize) {
        guard !mission.weatherList.isEmpty else { return }
        fog.texture = Self.fogTexture
        fog.colorBlendFactor = 1
        fog.alpha = 0
        fog.zPosition = 30.7
        addChild(fog)
        haze.size = size
        haze.alpha = 0
        haze.zPosition = 30.6
        addChild(haze)
        if mission.weatherList.contains(where: { $0.tint == "snow" || $0.tint == "sand" }) {
            drift.particleTexture = Art.fleck()
            drift.particleBirthRate = 0
            drift.particleLifetime = 2.2
            drift.particlePositionRange = CGVector(dx: 0, dy: size.height)
            drift.particleSpeed = 620
            drift.particleSpeedRange = 220
            drift.particleSize = CGSize(width: 9, height: 3)
            drift.particleAlpha = 0.7
            drift.particleAlphaRange = 0.3
            drift.zPosition = 30.8
            addChild(drift)
        }
        stormDim.color = SKColor(red: 0.05, green: 0.08, blue: 0.14, alpha: 1)
        stormDim.size = size
        stormDim.alpha = 0
        stormDim.zPosition = 29.5
        addChild(stormDim)
        sock.position = CGPoint(x: -size.width / 2 + 100, y: -size.height / 2 + 128)
        sock.zPosition = 34
        addChild(sock)
    }

    /// Opaque with a round clear patch in the middle: radius 0.05 of the width is clear, fully opaque from 0.12 on.
    private static let fogTexture: SKTexture = Art.texture(CGSize(width: 256, height: 256)) { ctx in
        let g = Art.gradient([(0, 0xffffff, 0), (0.05 / 0.5, 0xffffff, 0), (0.12 / 0.5, 0xffffff, 1), (1, 0xffffff, 1)])
        ctx.drawRadialGradient(g, startCenter: CGPoint(x: 128, y: 128), startRadius: 0, endCenter: CGPoint(x: 128, y: 128), endRadius: 128, options: [.drawsAfterEndLocation])
    }

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
        syncWeather(sim: sim, heli: heli, dt: dt)
        flashLevel *= CGFloat(exp(-9 * dt))
        flashNode.alpha = flashLevel > 0.02 ? flashLevel * (Int(flashLevel * 40) % 3 == 0 ? 0.6 : 1) : 0
    }

    private func syncWeather(sim: MissionSimulation, heli: CGPoint, dt: Double) {
        guard !mission.weatherList.isEmpty else { return }
        let f = sim.fog
        let k = CGFloat(min(1, dt * 2.5))
        fogSmooth += (CGFloat(f.density) - fogSmooth) * k
        fog.isHidden = fogSmooth < 0.01
        if !fog.isHidden {
            // The clear patch shrinks from the whole picture to a small circle around the helicopter.
            let clear = 700 - 580 * min(1, fogSmooth / 0.9)
            fog.size = CGSize(width: clear * 20, height: clear * 20)
            fog.position = heli
            var c = f.tint == "dust" ? (0.66, 0.55, 0.42) : (f.tint == "sand" ? (0.80, 0.62, 0.38) : (f.tint == "snow" ? (0.90, 0.93, 0.97) : (0.84, 0.86, 0.88)))
            if isNight { c = (c.0 * 0.22, c.1 * 0.22, c.2 * 0.24) }
            fog.color = SKColor(red: c.0, green: c.1, blue: c.2, alpha: 1)
            fog.alpha = min(0.96, 0.55 + fogSmooth * 0.5)
            haze.color = fog.color
            haze.alpha = fogSmooth * 0.3
        }
        haze.isHidden = fog.isHidden
        if drift.parent != nil {
            let blowing = f.tint == "snow" || f.tint == "sand" ? fogSmooth : 0
            drift.particleBirthRate = blowing > 0.05 ? 420 * blowing : 0
            let right = sim.wind >= 0
            drift.position = CGPoint(x: right ? -viewSize.width / 2 - 40 : viewSize.width / 2 + 40, y: 0)
            drift.emissionAngle = right ? 0 : .pi
            drift.particleColor = f.tint == "sand" ? SKColor(red: 0.90, green: 0.72, blue: 0.45, alpha: 1) : .white
            drift.particleColorBlendFactor = 1
        }
        let target = CGFloat(sim.thunderBuildup) * 0.42
        stormSmooth += (target - stormSmooth) * k
        stormDim.alpha = stormSmooth
        sock.update(wind: sim.wind, notices: sim.weatherNotices, time: sim.time, dt: dt)
    }
}

/// A windsock on the screen: streams in the direction the wind blows, hangs limp in calm air, and shows an amber arrow
/// with the seconds left before a gust or a wind shift in the direction it will blow.
final class WindSock: SKNode {
    private let pole = SKShapeNode()
    private var segments: [SKShapeNode] = []
    private let arrow = SKLabelNode(fontNamed: "Menlo-Bold")
    private var smooth: CGFloat = 0
    private var phase: CGFloat = 0

    override init() {
        super.init()
        let bg = SKShapeNode(rectOf: CGSize(width: 156, height: 78), cornerRadius: 3)
        bg.fillColor = SKColor(red: 0.11, green: 0.10, blue: 0.10, alpha: 0.38)
        bg.strokeColor = SKColor(white: 1, alpha: 0.14)
        bg.lineWidth = 1
        bg.position = CGPoint(x: 0, y: 6)
        bg.zPosition = -1
        addChild(bg)
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 0, y: -30)); p.addLine(to: CGPoint(x: 0, y: 26))
        pole.path = p
        pole.strokeColor = SKColor(white: 0.9, alpha: 0.9)
        pole.lineWidth = 3
        addChild(pole)
        for i in 0..<5 {
            let s = SKShapeNode()
            s.fillColor = i % 2 == 0 ? SKColor(red: 0.78, green: 0.36, blue: 0.23, alpha: 1) : SKColor(red: 0.95, green: 0.93, blue: 0.88, alpha: 1)
            s.strokeColor = .clear
            s.zPosition = 1
            addChild(s)
            segments.append(s)
        }
        arrow.fontSize = 14
        arrow.fontColor = SKColor(red: 1, green: 0.72, blue: 0.25, alpha: 1)
        arrow.horizontalAlignmentMode = .center
        arrow.verticalAlignmentMode = .center
        arrow.position = CGPoint(x: 0, y: -26)
        arrow.zPosition = 2
        addChild(arrow)
    }
    required init?(coder: NSCoder) { fatalError() }

    func update(wind: Double, notices: [WeatherNotice], time: Double, dt: Double) {
        // Wind acceleration of about 200 is a gale; the sock is fully out from about 130.
        let w = CGFloat(max(-1, min(1, wind / 130)))
        smooth += (w - smooth) * CGFloat(min(1, dt * 3))
        phase += CGFloat(dt) * (3 + 8 * abs(smooth))
        let dir: CGFloat = smooth >= 0 ? 1 : -1
        let strength = abs(smooth)
        // Droop from limp (hanging down) to horizontal.
        let droop = (1 - strength) * 1.25
        var x: CGFloat = 0, y: CGFloat = 24
        var ang: CGFloat = 0
        for (i, s) in segments.enumerated() {
            let flutter = sin(phase - CGFloat(i) * 0.9) * 0.10 * (0.3 + strength)
            ang = -droop * (0.45 + 0.17 * CGFloat(i)) + flutter
            let len: CGFloat = 13
            let w0 = 12 - CGFloat(i) * 1.6, w1 = w0 - 1.6
            let dx = cos(ang) * len * dir, dy = sin(ang) * len
            // Quad from the current end to the next one, thickness perpendicular to the direction.
            let nx = -sin(ang) * dir, ny = cos(ang)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: x + nx * w0 / 2, y: y + ny * w0 / 2))
            path.addLine(to: CGPoint(x: x + dx + nx * w1 / 2, y: y + dy + ny * w1 / 2))
            path.addLine(to: CGPoint(x: x + dx - nx * w1 / 2, y: y + dy - ny * w1 / 2))
            path.addLine(to: CGPoint(x: x - nx * w0 / 2, y: y - ny * w0 / 2))
            path.closeSubpath()
            s.path = path
            x += dx; y += dy
        }
        // Forecast: the arrow blinks in the direction of the coming wind.
        if let n = notices.first(where: { $0.direction != 0 }) {
            let on = Int(time * 3) % 2 == 0
            arrow.text = (n.direction > 0 ? "►" : "◄") + " \(Int(n.secondsLeft.rounded(.up))) s"
            arrow.isHidden = !on
        } else if let n = notices.first {
            arrow.text = (n.kind == "fog" ? "Nebel " : "Gewitter ") + "\(Int(n.secondsLeft.rounded(.up))) s"
            arrow.isHidden = Int(time * 3) % 2 != 0
        } else {
            arrow.isHidden = true
        }
    }
}
