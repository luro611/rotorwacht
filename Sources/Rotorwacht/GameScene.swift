import SpriteKit
import RotorwachtCore

/// The mission as seen on screen. Rules and physics live in RotorwachtCore's `MissionSimulation`;
/// this class only draws it and plays sounds.
final class GameScene: SKScene {
    static let viewSize = CGSize(width: 1280, height: 720)
    private static let step = 1.0 / 120

    let mission: Mission
    private(set) var sim: MissionSimulation
    var onHUD: ((HUDSnapshot) -> Void)?
    var onFinished: ((MissionResult) -> Void)?
    let audio = AudioEngine()
    var gamePaused = false { didSet { if !gamePaused { lastTime = 0 } } }

    // Nodes
    private let cam = SKCameraNode()
    private var heliRoot = SKNode()      // position + tilt
    private var heliFlip = SKNode()      // facing (xScale)
    private var heliSide: SKSpriteNode!
    private var heliFront: SKSpriteNode!
    private var rotorNode = SKNode()
    private var blades: [SKSpriteNode] = []
    private var rotorDisc: SKSpriteNode!
    private var water = SKSpriteNode()
    private var waveShape = SKShapeNode()
    private var waveFoam = SKShapeNode()
    private var sock = SKSpriteNode()
    private var personNodes: [Int: PersonNode] = [:]
    private var markers: [Int: SKSpriteNode] = [:]
    private var skyNode = SKSpriteNode()
    private var clouds: [(node: SKSpriteNode, base: CGFloat, speed: CGFloat, parallax: CGFloat)] = []
    private var parallaxLayers: [(node: SKNode, factor: CGFloat)] = []
    private let effects = SKNode()

    // State
    private var built = false
    private var lastTime: TimeInterval = 0
    private var accumulator = 0.0
    private var camPos = CGPoint(x: 640, y: 360)
    private var shake: CGFloat = 0
    private var rotorPhase: CGFloat = 0
    private var spawnTimer = 0.0
    private var hudTimer = 0.0
    private var clock = 0.0
    private var messages: [(text: String, until: Double)] = []
    private var lowFuelWarned = false
    private var thrustSmooth: Float = 0
    private var windStreakTimer = 0.0

    final class PersonNode: SKNode {
        let body = SKSpriteNode()
        let arm = SKSpriteNode()
        var waving = false
    }

    init(mission: Mission) {
        self.mission = mission
        self.sim = MissionSimulation(mission: mission)
        super.init(size: Self.viewSize)
        scaleMode = .aspectFit
        backgroundColor = SKColor(red: 0.36, green: 0.45, blue: 0.53, alpha: 1)
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: Scene setup

    override func didMove(to view: SKView) {
        guard !built else { return }
        built = true
        camera = cam
        addChild(cam)
        cam.position = camPos
        buildBackground()
        buildWorld()
        buildHelicopter()
        buildWeather()
        addChild(effects)
        effects.zPosition = 12
        let s = sim.heli
        camPos = CGPoint(x: min(max(s.x, 640), mission.world.width - 640), y: 360 + 80)
        applyCamera()
        say("Pfeil hoch startet den Hubschrauber. Hole die Menschen von den Dächern.", seconds: 9)
        audio.start()
    }

    func shutdown() { audio.stop() }

    private func buildBackground() {
        let size = Self.viewSize
        skyNode = SKSpriteNode(texture: Art.sky(size: size), size: size)
        skyNode.zPosition = -100
        cam.addChild(skyNode)

        // Clouds drifting at their own speed, fixed to the camera with a small parallax.
        for i in 0..<7 {
            let w = CGFloat(300 + (i * 97) % 220)
            let n = SKSpriteNode(texture: Art.cloud(width: w, seed: UInt64(10 + i), alpha: i % 3 == 0 ? 0.45 : 0.6))
            n.size = CGSize(width: w, height: w * 0.32)
            n.zPosition = -95
            n.position = CGPoint(x: -700 + CGFloat(i) * 230, y: 130 + CGFloat((i * 53) % 150))
            cam.addChild(n)
            clouds.append((n, n.position.x, CGFloat(4 + (i % 4) * 2), 0.03 + CGFloat(i % 3) * 0.015))
        }

        // Layers: far mountains (0.12), wooded hills (0.35)
        addParallax(factor: 0.12, z: -90, height: 460) { x0, w, h in Art.mountainChunk(x0: x0, w: w, h: h) }
        addParallax(factor: 0.35, z: -80, height: 400) { x0, w, h in Art.hillChunk(x0: x0, w: w, h: h) }
    }

    private func addParallax(factor f: CGFloat, z: CGFloat, height: CGFloat,
                             _ make: (CGFloat, CGFloat, CGFloat) -> SKTexture) {
        let total = CGFloat(mission.world.width) * f + 1280
        let layer = SKNode()
        layer.zPosition = z
        let chunk: CGFloat = 1024
        var x: CGFloat = 0
        while x < total {
            let w = min(chunk, total - x)
            let s = SKSpriteNode(texture: make(x, w, height))
            s.anchorPoint = .zero
            s.size = CGSize(width: w, height: height)
            s.position = CGPoint(x: x - 640, y: f * 360 - 420)
            layer.addChild(s)
            x += chunk
        }
        addChild(layer)
        parallaxLayers.append((layer, f))
    }

    private func buildWorld() {
        let terrain = SKNode()
        terrain.zPosition = -20
        addChild(terrain)
        let chunk: CGFloat = 1024
        let yMin: CGFloat = -120, yMax: CGFloat = 480
        var x: CGFloat = 0
        while x < CGFloat(mission.world.width) {
            let w = min(chunk, CGFloat(mission.world.width) - x)
            let s = SKSpriteNode(texture: Art.terrainChunk(mission: mission, x0: x, w: w, yMin: yMin, yMax: yMax))
            s.anchorPoint = .zero
            s.size = CGSize(width: w, height: yMax - yMin)
            s.position = CGPoint(x: x, y: yMin)
            terrain.addChild(s)
            x += chunk
        }

        // Buildings and markers at the rescue points
        for (i, p) in mission.rescuePoints.enumerated() {
            if p.kind != "island" {
                let tex = Art.building(kind: p.kind, width: CGFloat(p.width), top: CGFloat(p.top), seed: UInt64(40 + i))
                let n = SKSpriteNode(texture: tex)
                n.anchorPoint = CGPoint(x: 0.5, y: 1)
                n.position = CGPoint(x: p.x, y: p.top)
                n.zPosition = -10
                addChild(n)
            }
            let m = SKSpriteNode(texture: Art.marker())
            m.position = CGPoint(x: p.x, y: p.top + 110)
            m.zPosition = 4
            m.run(.repeatForever(.sequence([.moveBy(x: 0, y: 8, duration: 0.6), .moveBy(x: 0, y: -8, duration: 0.6)])))
            addChild(m)
            markers[i] = m
        }

        // People
        for person in sim.people {
            let node = PersonNode()
            node.body.texture = Art.person(variant: person.id)
            node.body.size = CGSize(width: 18, height: 30)
            node.body.anchorPoint = CGPoint(x: 0.5, y: 0)
            node.arm.texture = Art.arm()
            node.arm.size = CGSize(width: 4, height: 12)
            node.arm.anchorPoint = CGPoint(x: 0.5, y: 0.95)
            node.arm.position = CGPoint(x: 6, y: 20)
            node.addChild(node.body)
            node.addChild(node.arm)
            node.zPosition = 2
            addChild(node)
            personNodes[person.id] = node
        }

        // Camp
        let campWidth = CGFloat(mission.base.width)
        let camp = SKSpriteNode(texture: Art.camp(width: campWidth))
        camp.anchorPoint = CGPoint(x: 0.5, y: 0)
        camp.position = CGPoint(x: mission.base.x, y: mission.baseSurface)
        camp.zPosition = -9
        addChild(camp)
        sock = SKSpriteNode(texture: Art.sock())
        sock.anchorPoint = CGPoint(x: 0, y: 0.5)
        sock.position = CGPoint(x: mission.base.x - 2, y: mission.baseSurface + 100)
        sock.zPosition = -8
        addChild(sock)

        // Water: body + animated wave top
        water = SKSpriteNode(texture: Art.waterBody(height: 900))
        water.anchorPoint = CGPoint(x: 0.5, y: 1)
        water.size = CGSize(width: 1500, height: 900)
        water.zPosition = 5
        addChild(water)
        waveShape.fillColor = SKColor(red: 0.37, green: 0.55, blue: 0.60, alpha: 0.72)
        waveShape.strokeColor = .clear
        waveShape.zPosition = 5.1
        addChild(waveShape)
        waveFoam.strokeColor = SKColor(white: 1, alpha: 0.55)
        waveFoam.lineWidth = 2
        waveFoam.zPosition = 5.2
        addChild(waveFoam)
    }

    private func buildHelicopter() {
        heliRoot.zPosition = 10
        addChild(heliRoot)
        heliRoot.addChild(heliFlip)
        heliSide = SKSpriteNode(texture: Art.helicopterSide(), size: CGSize(width: 132, height: 60))
        heliSide.anchorPoint = CGPoint(x: 0.5, y: 0)
        heliSide.position = CGPoint(x: -4, y: 0)
        heliFlip.addChild(heliSide)
        heliFront = SKSpriteNode(texture: Art.helicopterFront(), size: CGSize(width: 74, height: 60))
        heliFront.anchorPoint = CGPoint(x: 0.5, y: 0)
        heliRoot.addChild(heliFront)
        rotorDisc = SKSpriteNode(texture: Art.rotorDisc(), size: CGSize(width: 150, height: 14))
        rotorNode.addChild(rotorDisc)
        for _ in 0..<2 {
            let b = SKSpriteNode(texture: Art.rotorBlade(), size: CGSize(width: 150, height: 6))
            blades.append(b)
            rotorNode.addChild(b)
        }
        rotorNode.position = CGPoint(x: 0, y: 59)
        rotorNode.zPosition = 1
        heliRoot.addChild(rotorNode)
    }

    private func buildWeather() {
        let rain = SKEmitterNode()
        rain.particleTexture = Art.raindrop()
        rain.particleBirthRate = 260
        rain.particleLifetime = 1.1
        rain.particlePositionRange = CGVector(dx: 1700, dy: 0)
        rain.position = CGPoint(x: 0, y: 420)
        rain.emissionAngle = CGFloat.pi * 1.5 + 0.12
        rain.particleSpeed = 820
        rain.particleSpeedRange = 120
        rain.particleAlpha = 0.28
        rain.particleSize = CGSize(width: 3, height: 22)
        rain.particleRotation = 0.12
        rain.zPosition = 30
        cam.addChild(rain)
        rain.advanceSimulationTime(1.2)

        let dim = SKSpriteNode(color: SKColor(red: 0.10, green: 0.16, blue: 0.20, alpha: 0.14), size: Self.viewSize)
        dim.zPosition = 29
        cam.addChild(dim)
    }

    // MARK: Frame loop

    override func update(_ currentTime: TimeInterval) {
        guard built else { return }
        if lastTime == 0 { lastTime = currentTime }
        var dt = currentTime - lastTime
        lastTime = currentTime
        dt = min(max(dt, 0), 1.0 / 15)
        clock += dt

        if !gamePaused && !sim.isFinished {
            accumulator += dt
            var events: [SimEvent] = []
            var n = 0
            let input = InputController.shared.pilot
            while accumulator >= Self.step && n < 8 {
                events += sim.step(input: input, dt: Self.step)
                accumulator -= Self.step
                n += 1
            }
            handle(events)
            if let r = sim.result, !finishedSent {
                finishedSent = true
                DispatchQueue.main.async { [weak self] in self?.onFinished?(r) }
            }
        }
        syncVisuals(dt: gamePaused ? 0 : dt)
        updateCamera(dt: dt)
        hudTimer -= dt
        if hudTimer <= 0 { hudTimer = 1.0 / 12; pushHUD() }
    }
    private var finishedSent = false

    // MARK: Events

    private func say(_ text: String, seconds: Double = 5) {
        messages.append((text, clock + seconds))
        if messages.count > 3 { messages.removeFirst() }
    }

    private func handle(_ events: [SimEvent]) {
        for e in events {
            switch e {
            case .physics(let p):
                switch p {
                case .touchdown(let v, let d):
                    audio.play(.thump(Float(min(1, v / 200)) * 0.8 + 0.2))
                    if d > 0 {
                        shake = max(shake, min(14, CGFloat(d) / 2 + 3))
                        say("Harte Landung: \(Int(d.rounded())) % Haltbarkeit verloren.")
                    }
                case .collision(let d):
                    if d > 0.5 {
                        audio.play(.thump(0.9))
                        shake = max(shake, min(14, CGFloat(d) + 3))
                        say("Zusammenstoß: \(Int(d.rounded())) % Haltbarkeit verloren.")
                    }
                case .splash(let v):
                    audio.play(.splash)
                    spawnSpray(count: Int(min(24, v / 8)), strong: true)
                    if v > 60 { say("Im Wasser gelandet. Sofort wieder hoch!") }
                case .liftoff: break
                case .outOfFuel:
                    audio.play(.alarm)
                    say("Treibstoff leer. Notlandung!", seconds: 6)
                }
            case .boarded: audio.play(.ding)
            case .rescued: audio.play(.rescued)
            case .lost(_, let pi):
                audio.play(.alarm)
                say("Das Wasser hat \(mission.rescuePoints[pi].name) erreicht. Menschen verloren.", seconds: 6)
            case .floodWarning(let pi):
                audio.play(.warn)
                say("Wasser steigt: \(mission.rescuePoints[pi].name) bald überflutet.", seconds: 6)
            case .cabinFull:
                audio.play(.warn)
                say("Kabine voll. Bringe die Menschen ins Lager rechts.", seconds: 6)
            case .helicopterLost(let remaining):
                audio.play(.crash)
                shake = 18
                spawnExplosion()
                say(remaining > 0 ? "Hubschrauber verloren. Noch \(remaining) im Einsatz." : "Der letzte Hubschrauber ist verloren.", seconds: 6)
            case .respawned:
                say("Ersatzhubschrauber im Lager bereit.")
                lowFuelWarned = false
            case .finished: break
            }
        }
    }

    // MARK: Visual sync

    private func syncVisuals(dt: Double) {
        let h = sim.heli
        let crashed: Bool = { if case .crashed = sim.phase { return true } else { return false } }()
        let finished = sim.isFinished
        heliRoot.isHidden = crashed || (finished && sim.heli.durability <= 0)
        heliRoot.position = CGPoint(x: h.x, y: h.y)
        heliRoot.zRotation = CGFloat(-h.tilt)
        // Facing: blend between front view and side view.
        let f = CGFloat(h.facing)
        let sideVisible = abs(f) > 0.45
        heliSide.isHidden = !sideVisible
        heliFront.isHidden = sideVisible
        heliFlip.xScale = f == 0 ? 1 : (f > 0 ? 1 : -1) * max(abs(f), 0.5)
        heliFront.xScale = 1

        // Rotor
        let engineOn = h.fuel > 0 && !crashed
        let spin: CGFloat = engineOn ? 52 : 8
        rotorPhase += spin * CGFloat(dt)
        for (i, b) in blades.enumerated() {
            let p = rotorPhase + CGFloat(i) * .pi / 2
            b.xScale = abs(cos(p)) * 0.9 + 0.1
        }
        rotorDisc.alpha = engineOn ? 1 : 0.15
        rotorNode.xScale = sideVisible ? 1 : 1.15

        // Water
        let level = CGFloat(sim.floodLevel)
        let left = cam.position.x - 760
        water.position = CGPoint(x: cam.position.x, y: level - 8)
        let wave = CGMutablePath()
        let foam = CGMutablePath()
        let t = CGFloat(clock)
        var x = left
        var first = true
        while x <= left + 1520 {
            let y = level + 3.2 * sin(x * 0.02 + t * 1.6) + 2.0 * sin(x * 0.045 - t * 2.3)
            if first { wave.move(to: CGPoint(x: x, y: y)); foam.move(to: CGPoint(x: x, y: y)); first = false }
            else { wave.addLine(to: CGPoint(x: x, y: y)); foam.addLine(to: CGPoint(x: x, y: y)) }
            x += 20
        }
        wave.addLine(to: CGPoint(x: left + 1520, y: level - 14))
        wave.addLine(to: CGPoint(x: left, y: level - 14))
        wave.closeSubpath()
        waveShape.path = wave
        waveFoam.path = foam

        // People
        for p in sim.people {
            guard let node = personNodes[p.id] else { continue }
            let gy = CGFloat(mission.surfaceHeight(at: p.spotX))
            switch p.state {
            case .waiting:
                node.isHidden = false
                node.position = CGPoint(x: p.spotX, y: gy)
                setWaving(node, true)
                node.xScale = p.spotX < h.x ? 1 : -1
            case .boarding:
                node.isHidden = false
                let t = CGFloat(p.progress)
                node.position = CGPoint(x: p.spotX + (CGFloat(h.x) - CGFloat(p.spotX)) * t, y: gy)
                node.alpha = 1 - t * t
                setWaving(node, false)
                node.xScale = CGFloat(h.x) > CGFloat(p.spotX) ? -1 : 1
            case .aboard, .injured:
                node.isHidden = true
            case .leaving:
                node.isHidden = false
                let t = CGFloat(p.progress)
                let targetX = CGFloat(mission.base.x - mission.base.width / 2 + 40 + CGFloat(p.id % 5) * 12)
                node.position = CGPoint(x: CGFloat(h.x) + (targetX - CGFloat(h.x)) * t, y: CGFloat(mission.baseSurface) + 8)
                node.alpha = 1
                setWaving(node, false)
                node.xScale = targetX > CGFloat(h.x) ? -1 : 1
            case .rescued:
                node.isHidden = false
                let targetX = CGFloat(mission.base.x - mission.base.width / 2 + 40 + CGFloat(p.id % 5) * 12)
                node.position = CGPoint(x: targetX, y: CGFloat(mission.baseSurface) + 8)
                node.alpha = 1
                setWaving(node, p.id % 2 == 0)
            case .lost:
                node.isHidden = true
            }
        }
        for (i, m) in markers {
            let waiting = sim.people.contains { $0.pointIndex == i && ($0.state == .waiting || $0.state == .boarding) }
            m.isHidden = !waiting
        }

        // Windsock
        let w = CGFloat(sim.wind)
        let dir: CGFloat = w >= 0 ? 1 : -1
        sock.xScale = dir
        let strength = min(1, abs(w) / 140)
        sock.zRotation = (1 - strength) * -1.1 * dir * dir // droops when calm
        sock.yScale = 0.7 + 0.3 * strength

        // Rotor wash near the floor
        spawnTimer -= dt
        let floor = max(mission.maxSurface(from: h.x - 40, to: h.x + 40), sim.floodLevel)
        let above = h.y - floor
        if !h.onGround || above < 4, engineOn, above < 110, spawnTimer <= 0, !gamePaused {
            spawnTimer = 0.04
            let wet = sim.floodLevel > mission.maxSurface(from: h.x - 40, to: h.x + 40)
            spawnWash(x: h.x, y: floor, wet: wet, power: 1 - above / 110)
        }

        // Wind streaks during gusts
        windStreakTimer -= dt
        if abs(sim.wind) > 70, windStreakTimer <= 0, !gamePaused {
            windStreakTimer = 0.05
            spawnWindStreak()
        }

        // Clouds
        for c in clouds {
            var x = c.base + CGFloat(clock) * c.speed - (camPos.x * c.parallax)
            x = (x + 1100).truncatingRemainder(dividingBy: 2200)
            if x < 0 { x += 2200 }
            c.node.position.x = x - 1100
        }

        // Audio
        let up = InputController.shared.up, down = InputController.shared.down
        let target: Float = engineOn ? (up ? 1 : (down ? 0.15 : 0.5)) + Float(min(1, abs(h.vx) / 280)) * 0.3 : 0
        thrustSmooth += (target - thrustSmooth) * Float(min(1, dt * 4))
        audio.thrust = min(1, thrustSmooth)
        audio.rotorSpeed = engineOn ? 1 : 0.1
        audio.wind = Float(min(1, abs(sim.wind) / 200)) * 0.8 + 0.12
        if h.fuel < mission.fuel.capacity * 0.2, h.fuel > 0, !lowFuelWarned, !h.onGround {
            lowFuelWarned = true
            audio.play(.warn)
            say("Treibstoff knapp. Zurück ins Lager!")
        }
        if h.fuel > mission.fuel.capacity * 0.5 { lowFuelWarned = false }
    }

    private func setWaving(_ node: PersonNode, _ on: Bool) {
        if node.waving == on { return }
        node.waving = on
        node.arm.removeAllActions()
        if on {
            node.arm.run(.repeatForever(.sequence([.rotate(toAngle: 2.6, duration: 0.28), .rotate(toAngle: 3.5, duration: 0.28)])))
        } else {
            node.arm.zRotation = 0
        }
    }

    // MARK: Camera

    private func updateCamera(dt: Double) {
        let h = sim.heli
        let look = CGFloat(h.vx) * 0.55
        let tx = min(max(CGFloat(h.x) + look, 640), CGFloat(mission.world.width) - 640)
        let ty = min(max(CGFloat(h.y) + 120, 360), 760)
        let k = CGFloat(1 - exp(-3.5 * dt))
        camPos.x += (tx - camPos.x) * k
        camPos.y += (ty - camPos.y) * CGFloat(1 - exp(-2.5 * dt))
        shake *= CGFloat(exp(-6 * dt))
        applyCamera()
    }

    private func applyCamera() {
        let sx = shake > 0.2 ? CGFloat.random(in: -shake...shake) : 0
        let sy = shake > 0.2 ? CGFloat.random(in: -shake...shake) : 0
        cam.position = CGPoint(x: camPos.x + sx, y: camPos.y + sy)
        for (node, f) in parallaxLayers {
            node.position = CGPoint(x: camPos.x * (1 - f), y: camPos.y * (1 - f))
        }
    }

    // MARK: Effects

    private func spawnWash(x: Double, y: Double, wet: Bool, power: Double) {
        for _ in 0..<2 {
            let p = SKSpriteNode(texture: Art.puff())
            let s = CGFloat.random(in: 0.5...1.0) * CGFloat(0.5 + power)
            p.size = CGSize(width: 32 * s, height: 32 * s)
            p.color = wet ? SKColor(red: 0.85, green: 0.93, blue: 0.95, alpha: 1) : SKColor(red: 0.62, green: 0.55, blue: 0.42, alpha: 1)
            p.colorBlendFactor = wet ? 0.1 : 0.8
            p.alpha = CGFloat(0.25 + 0.35 * power)
            let dir: CGFloat = Bool.random() ? 1 : -1
            p.position = CGPoint(x: x + Double(dir) * Double.random(in: 10...50), y: y + 4)
            effects.addChild(p)
            p.run(.sequence([
                .group([.moveBy(x: dir * CGFloat.random(in: 60...150), y: CGFloat.random(in: 6...26), duration: 0.7),
                        .fadeOut(withDuration: 0.7), .scale(to: 1.8, duration: 0.7)]),
                .removeFromParent()]))
        }
    }

    private func spawnSpray(count: Int, strong: Bool) {
        let h = sim.heli
        for _ in 0..<max(4, count) {
            let p = SKSpriteNode(texture: Art.puff())
            p.size = CGSize(width: 18, height: 18)
            p.alpha = 0.7
            p.position = CGPoint(x: h.x + Double.random(in: -40...40), y: sim.floodLevel + 4)
            effects.addChild(p)
            p.run(.sequence([
                .group([.moveBy(x: CGFloat.random(in: -90...90), y: CGFloat.random(in: 30...110), duration: 0.6), .fadeOut(withDuration: 0.6)]),
                .removeFromParent()]))
        }
    }

    private func spawnExplosion() {
        let h = sim.heli
        for i in 0..<26 {
            let p = SKSpriteNode(texture: Art.puff())
            let s = CGFloat.random(in: 0.8...2.4)
            p.size = CGSize(width: 32 * s, height: 32 * s)
            p.color = i % 3 == 0 ? SKColor(red: 1, green: 0.62, blue: 0.2, alpha: 1) : SKColor(white: 0.25, alpha: 1)
            p.colorBlendFactor = 0.9
            p.position = CGPoint(x: h.x, y: h.y + 30)
            effects.addChild(p)
            let a = CGFloat.random(in: 0...(2 * .pi)), d = CGFloat.random(in: 40...170)
            p.run(.sequence([.group([.moveBy(x: cos(a) * d, y: sin(a) * d + 40, duration: 1.1), .fadeOut(withDuration: 1.1)]), .removeFromParent()]))
        }
    }

    private func spawnWindStreak() {
        let dir: CGFloat = sim.wind >= 0 ? 1 : -1
        let s = SKSpriteNode(color: SKColor(white: 1, alpha: 0.35), size: CGSize(width: CGFloat.random(in: 60...160), height: 1.5))
        s.position = CGPoint(x: cam.position.x - dir * 700, y: cam.position.y + CGFloat.random(in: -300...300))
        s.zPosition = 28
        addChild(s)
        s.run(.sequence([.moveBy(x: dir * 1500, y: 0, duration: 0.8), .removeFromParent()]))
    }

    // MARK: HUD

    private func pushHUD() {
        messages.removeAll { $0.until < clock }
        var snap = HUDSnapshot()
        let h = sim.heli
        snap.fuel = h.fuel / mission.fuel.capacity
        snap.durability = h.durability / sim.spec.maxDurability
        snap.aboard = sim.aboardCount
        snap.capacity = mission.capacity
        snap.rescued = sim.rescuedCount
        snap.total = sim.people.count
        snap.lost = sim.lostCount + sim.injuredCount
        snap.timeLeft = sim.timeLeft
        snap.helicoptersLeft = sim.helicoptersLeft
        snap.helicoptersTotal = mission.helicopters
        snap.wind = sim.wind
        snap.floodLevel = sim.floodLevel
        snap.heliX = h.x
        snap.worldWidth = mission.world.width
        snap.baseX = mission.base.x
        snap.points = mission.rescuePoints.enumerated().map { i, p in
            let waiting = sim.people.filter { $0.pointIndex == i && $0.state == .waiting }.count
            return MiniMapPoint(x: p.x, waiting: waiting, endangered: sim.floodLevel > p.top - 35)
        }
        snap.messages = messages.map { $0.text }
        if case .crashed = sim.phase { snap.crashed = true }
        onHUD?(snap)
    }
}
