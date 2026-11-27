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
    private let heliSprite = HeliSprite()
    private let heliShadow = SKSpriteNode()
    private var spool: CGFloat = 0
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
    private let flameLayer = SKNode()
    private let smokeLayer = SKNode()
    private var lakeNodes: [(spec: LakeSpec, body: SKSpriteNode, shape: SKShapeNode, foam: SKShapeNode)] = []
    private final class FireNode {
        let flame: SKEmitterNode
        let smoke: SKEmitterNode
        let scorch: SKSpriteNode
        init(flame: SKEmitterNode, smoke: SKEmitterNode, scorch: SKSpriteNode) {
            self.flame = flame; self.smoke = smoke; self.scorch = scorch
        }
    }
    private var fireNodes: [Int: FireNode] = [:]
    private var dropNodes: [Int: SKSpriteNode] = [:]
    private let smokeOverlay = SKSpriteNode()
    private let heatOverlay = SKSpriteNode()
    private var smokeSmooth: CGFloat = 0
    private var heatSmooth: CGFloat = 0
    private var fillSprayTimer = 0.0
    private var hurtSaid: Set<Int> = []
    private var lostSaid: Set<Int> = []
    private var waveTimer = 0.0
    private var lakeTimer = 0.0
    private var fireSaid = false
    private var hazards: HazardLayer?
    private var passages: PassageLayer?
    private var obstacles: ObstacleLayer?
    private var atmosphere: AtmosphereLayer?
    private let cable = SKShapeNode()
    private var beacons: [Int: SKSpriteNode] = [:]
    private var padNodes: [Int: SKSpriteNode] = [:]
    private var said: Set<String> = []
    private var surfTimer = 0.0
    private var cableHint = 0.0
    private lazy var look = Look.of(mission)

    // State
    private var built = false
    private var lastTime: TimeInterval = 0
    private var accumulator = 0.0
    private var camPos = CGPoint(x: 640, y: 360)
    private var shake: CGFloat = 0
    private var spawnTimer = 0.0
    private var hudTimer = 0.0
    private var clock = 0.0
    private var messages: [(text: String, until: Double)] = []
    private var lowFuelWarned = false
    private var thrustSmooth: Float = 0
    private var windStreakTimer = 0.0

    final class PersonNode: SKNode {
        let fig: FigureSprite
        init(id: Int) { fig = FigureSprite(id: id); super.init(); addChild(fig) }
        required init?(coder: NSCoder) { fatalError() }
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
        let hl = HazardLayer(mission: mission)
        hl.onThunder = { [weak self] x in self?.thunder(at: x) }
        addChild(hl)
        hazards = hl
        if !mission.passageList.isEmpty {
            let pl = PassageLayer(mission: mission)
            addChild(pl)
            passages = pl
        }
        if !mission.obstacleList.isEmpty {
            let ol = ObstacleLayer(mission: mission)
            addChild(ol)
            obstacles = ol
        }
        cable.strokeColor = SKColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1)
        cable.lineWidth = 2
        cable.zPosition = 9
        cable.isHidden = true
        addChild(cable)
        flameLayer.zPosition = 3.5
        addChild(flameLayer)
        smokeLayer.zPosition = 11.5
        addChild(smokeLayer)
        addChild(effects)
        effects.zPosition = 12
        let s = sim.heli
        camPos = CGPoint(x: min(max(s.x, 640), mission.world.width - 640), y: 360 + 80)
        applyCamera()
        if let intro = introMessage() {
            say(intro, seconds: 10)
        } else if mission.isFire {
            say("Pfeil hoch startet. Tief über dem See füllt sich der Tank, die Leertaste wirft Löschwasser ab.", seconds: 10)
        } else {
            say("Pfeil hoch startet den Hubschrauber. Hole die Menschen von den Dächern.", seconds: 9)
        }
        audio.start()
    }

    func shutdown() { audio.stop() }

    /// First hint of a newer Einsatz, shown on the ground before take-off.
    private func introMessage() -> String? {
        switch mission.hazard {
        case "rig": return "Pfeil hoch startet. Feuer an Deck: Tank tief über dem Meer füllen, Leertaste löscht. Schiff und Floß schwanken, sanft aufsetzen."
        case "surge": return "Pfeil hoch startet. Der Damm ist gebrochen: Eine Flutwelle läuft durch die Schlucht. Hole zuerst die Tiefsten, und flieg unter den Brücken durch."
        case "blizzard": return "Pfeil hoch startet. Der Hubschrauber vereist im Flug: Im Lager oder am Außenposten taut er wieder auf. Die Sicht wird schlecht."
        case "sandstorm": return "Pfeil hoch startet. Hitze kostet Treibstoff: Tanke an den Außenposten. Sandstürme nehmen die Sicht."
        case "storm": return "Pfeil hoch startet. Dein Scheinwerfer leuchtet nach vorn. Ein roter Strahl kündigt einen Blitz an: flieg zur Seite."
        case "quake": return "Pfeil hoch startet. Die Gassen sind eng: flieg über die Häuser und lande senkrecht auf den Plätzen."
        case "volcano": return "Pfeil hoch startet. Lavabrocken fliegen auf gestrichelten Bahnen. Außenposten tanken: lande auf einem."
        case "avalanche": return "Pfeil hoch startet. An Felsvorsprüngen nicht landen: schwebe ruhig darüber, Pfeil runter holt das Seil näher."
        default: return nil
        }
    }

    /// First hint when a passage comes close.
    private func passageHints() {
        for p in mission.passageList where abs(sim.heli.x - (p.x0 + p.x1) / 2) < (p.x1 - p.x0) / 2 + 520 {
            if p.isTunnel {
                sayOnce("tunnel", "Tunnel mit Shuttern: Gelb blinkt vor dem Schließen, Rot heißt zu. Wer im Tor steckt, verliert den Hubschrauber.", seconds: 8)
            } else {
                sayOnce("bridge", "Unterführung: Man kommt nur darunter durch, über die Brücke geht es nicht. Nicht die Decke berühren.", seconds: 7)
            }
        }
    }

    private func sayOnce(_ key: String, _ text: String, seconds: Double = 6) {
        if said.insert(key).inserted { say(text, seconds: seconds) }
    }

    private func thunder(at x: CGFloat) {
        atmosphere?.flash(0.85)
        let near = 1 - min(1, abs(x - CGFloat(sim.heli.x)) / 1400)
        audio.play(.thunder(Float(0.35 + 0.65 * near)))
        shake = max(shake, 4 + 6 * near)
    }

    private func buildBackground() {
        let size = Self.viewSize
        skyNode = SKSpriteNode(texture: Art.sky(size: size, look: look), size: size)
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

        // Layers: far mountains (0.12), wooded hills (0.35): rendered panoramas, code-drawn chunks as fallback
        addPanorama(name: "far", factor: 0.12, z: -90, height: 460) { x0, w, h in Art.mountainChunk(x0: x0, w: w, h: h, look: look) }
        addPanorama(name: "hill", factor: 0.35, z: -80, height: 400) { x0, w, h in Art.hillChunk(x0: x0, w: w, h: h, look: look) }
    }

    private func addPanorama(name: String, factor f: CGFloat, z: CGFloat, height: CGFloat,
                             _ fallback: (CGFloat, CGFloat, CGFloat) -> SKTexture) {
        guard let tex = Render.texture("panorama", "\(name)-\(mission.id)") else {
            addParallax(factor: f, z: z, height: height, fallback)
            return
        }
        let total = CGFloat(mission.world.width) * f + 1280
        let layer = SKNode()
        layer.zPosition = z
        let s = SKSpriteNode(texture: tex, size: CGSize(width: total.rounded(.down), height: height))
        s.anchorPoint = .zero
        s.position = CGPoint(x: -640, y: f * 360 - 420)
        layer.addChild(s)
        addChild(layer)
        parallaxLayers.append((layer, f))
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
        // Tall mountains need a taller picture; the view never reaches below world y = 0.
        let lowest = CGFloat(mission.terrain.map(\.y).min() ?? 0), highest = CGFloat(mission.terrain.map(\.y).max() ?? 0)
        let yMin: CGFloat = max(-120, min(0, lowest - 10)), yMax: CGFloat = max(480, highest + 40)
        var x: CGFloat = 0
        var index = 0
        while x < CGFloat(mission.world.width) {
            let w = min(chunk, CGFloat(mission.world.width) - x)
            let s: SKSpriteNode
            if let t = Render.texture("terrain", "\(mission.id)-\(index)") {
                s = SKSpriteNode(texture: t)
                s.size = CGSize(width: chunk, height: yMax - yMin)   // the render always covers a full chunk
            } else {
                s = SKSpriteNode(texture: Art.terrainChunk(mission: mission, x0: x, w: w, yMin: yMin, yMax: yMax))
                s.size = CGSize(width: w, height: yMax - yMin)
            }
            s.anchorPoint = .zero
            s.position = CGPoint(x: x, y: yMin)
            terrain.addChild(s)
            x += chunk
            index += 1
        }

        // Landing pads (rendered per rescue point) and markers
        for (i, p) in mission.rescuePoints.enumerated() {
            if let n = Render.padSprite("pad-\(mission.id)-\(p.id)") {
                n.position = CGPoint(x: p.x, y: p.top)
                n.zPosition = p.kind == "boat" ? 4.9 : -10
                addChild(n)
                padNodes[i] = n
            }
            let m = SKSpriteNode(texture: Art.marker())
            m.position = CGPoint(x: p.x, y: p.top + 110)
            m.zPosition = 4
            m.run(.repeatForever(.sequence([.moveBy(x: 0, y: 8, duration: 0.6), .moveBy(x: 0, y: -8, duration: 0.6)])))
            addChild(m)
            markers[i] = m
            if mission.isNight {
                let g = SKSpriteNode(texture: Art.beaconGlow(), size: CGSize(width: 150, height: 150))
                g.position = CGPoint(x: p.x, y: p.top + 14)
                g.zPosition = 26
                g.blendMode = .add
                g.run(.repeatForever(.sequence([.fadeAlpha(to: 0.55, duration: 0.7), .fadeAlpha(to: 1, duration: 0.7)])))
                addChild(g)
                beacons[i] = g
            }
        }

        // Outposts for refuelling
        for o in mission.outpostList {
            let n = SKSpriteNode(texture: Art.outpost(width: CGFloat(o.width)))
            n.anchorPoint = CGPoint(x: 0.5, y: 0)
            n.position = CGPoint(x: o.x, y: mission.groundHeight(at: o.x))
            n.zPosition = -9
            addChild(n)
        }
        if mission.isNight {
            for x in [mission.base.x] + mission.outpostList.map(\.x) {
                let g = SKSpriteNode(texture: Art.beaconGlow(), size: CGSize(width: 320, height: 200))
                g.position = CGPoint(x: x, y: mission.groundHeight(at: x) + 20)
                g.zPosition = 26
                g.blendMode = .add
                g.alpha = 0.7
                addChild(g)
            }
        }

        // People
        for person in sim.people {
            let node = PersonNode(id: person.id)
            node.zPosition = 2
            addChild(node)
            personNodes[person.id] = node
        }

        // Camp
        if let camp = Render.padSprite("pad-camp") {
            camp.position = CGPoint(x: mission.base.x, y: mission.baseSurface)
            camp.zPosition = -9
            addChild(camp)
        }
        sock = SKSpriteNode(texture: Art.sock())
        sock.anchorPoint = CGPoint(x: 0, y: 0.5)
        sock.position = CGPoint(x: mission.base.x + mission.base.width / 2 - 48, y: mission.baseSurface + 100)
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

        // Lakes: still water at a fixed level.
        for l in mission.lakeList {
            let w = CGFloat(l.x1 - l.x0)
            let body = SKSpriteNode(texture: Art.waterBody(height: 700))
            body.anchorPoint = CGPoint(x: 0.5, y: 1)
            body.size = CGSize(width: w, height: 700)
            body.position = CGPoint(x: CGFloat((l.x0 + l.x1) / 2), y: CGFloat(l.level) - 8)
            body.zPosition = 5
            addChild(body)
            let shape = SKShapeNode()
            shape.fillColor = SKColor(red: 0.37, green: 0.55, blue: 0.60, alpha: 0.72)
            shape.strokeColor = .clear
            shape.zPosition = 5.1
            addChild(shape)
            let foam = SKShapeNode()
            foam.strokeColor = SKColor(white: 1, alpha: 0.5)
            foam.lineWidth = 2
            foam.zPosition = 5.2
            addChild(foam)
            lakeNodes.append((l, body, shape, foam))
        }
    }

    private func buildHelicopter() {
        heliShadow.texture = Art.puff()
        heliShadow.color = SKColor(white: 0, alpha: 1)
        heliShadow.colorBlendFactor = 1
        heliShadow.zPosition = 3
        addChild(heliShadow)
        heliRoot.zPosition = 10
        addChild(heliRoot)
        heliRoot.addChild(heliSprite)
    }

    private func buildWeather() {
        // Smoke and heat over the whole picture (invisible until there is fire nearby).
        smokeOverlay.color = SKColor(red: 0.20, green: 0.17, blue: 0.15, alpha: 1)
        smokeOverlay.size = Self.viewSize
        smokeOverlay.alpha = 0
        smokeOverlay.zPosition = 31
        cam.addChild(smokeOverlay)
        heatOverlay.color = SKColor(red: 1.0, green: 0.42, blue: 0.12, alpha: 1)
        heatOverlay.size = Self.viewSize
        heatOverlay.alpha = 0
        heatOverlay.zPosition = 32
        cam.addChild(heatOverlay)

        if mission.atmosphere != nil || !mission.weatherList.isEmpty {
            let a = AtmosphereLayer(mission: mission, size: Self.viewSize, weatherOnly: mission.atmosphere == nil)
            cam.addChild(a)
            atmosphere = a
            // With an `atmosphere` block this layer does everything; without one it only adds the weather schedule.
            if mission.atmosphere != nil { return }
        }

        if mission.isFire {
            let haze = SKSpriteNode(color: SKColor(red: 0.95, green: 0.62, blue: 0.30, alpha: 0.10), size: Self.viewSize)
            haze.zPosition = 29
            cam.addChild(haze)
            return
        }

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
            hazards?.handle(e, sim: sim)
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
            case .fireStarted:
                audio.play(.ignite)
                let first = mission.hazard == "rig" ? "Feuer an Deck! Es läuft auf die Wartenden zu. Lösche mit der Leertaste." : "Feuer! Es läuft bergauf auf die Wartenden zu. Lösche mit der Leertaste."
                say(fireSaid ? "Ein neues Feuer ist ausgebrochen." : first, seconds: 7)
                fireSaid = true
            case .fireWarning(let pi):
                audio.play(.warn)
                say("Feuer nähert sich: \(mission.rescuePoints[pi].name). Löschen oder abholen!", seconds: 6)
            case .hurtByFire(_, let pi):
                if hurtSaid.insert(pi).inserted {
                    audio.play(.alarm)
                    say("\(mission.rescuePoints[pi].name): Menschen vom Feuer verletzt.", seconds: 6)
                }
            case .scorched:
                shake = max(shake, 3)
                say("Hitze! Die Haltbarkeit sinkt. Flieg höher oder lösche die Flammen.", seconds: 4)
            case .tankFull:
                audio.play(.ding)
                say("Tank voll.", seconds: 2)
            case .tankEmpty:
                say("Tank leer. Tief über See oder Fluss füllen, oder im Lager.", seconds: 5)
            case .boarded: audio.play(.ding)
            case .rescued: audio.play(.rescued)
            case .lost(_, let pi):
                guard lostSaid.insert(pi).inserted else { break }
                audio.play(.alarm)
                let name = mission.rescuePoints[pi].name
                switch mission.hazard {
                case "volcano": say("Die Lava hat \(name) erreicht. Menschen verloren.", seconds: 6)
                case "avalanche": say("Die Lawine hat \(name) erfasst. Menschen verloren.", seconds: 6)
                case "surge": say("Die Flutwelle hat \(name) erreicht. Menschen verloren.", seconds: 6)
                default: say("Das Wasser hat \(name) erreicht. Menschen verloren.", seconds: 6)
                }
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
            case .strikeWarning:
                audio.play(.warn)
                sayOnce("strike", "Blitz im Anmarsch: Verlasse den roten Kreis, bevor der Strahl einschlägt.", seconds: 7)
            case .lightning(_, let hit):
                if hit { sayOnce("hit\(Int(clock))", "Blitzschlag! Die Haltbarkeit sinkt.", seconds: 4) }
            case .tremor(let kind, _):
                audio.play(.rumble)
                if kind == "lavaBomb" { sayOnce("bombs", "Der Vulkan grollt: Lavabrocken. Achte auf die gestrichelten Flugbahnen.", seconds: 7) }
                else { say("Nachbeben! Trümmer fallen gleich: Weg von den Plätzen.", seconds: 5) }
            case .objectLaunched(let kind):
                if kind == "lavaBomb" { audio.play(.pop) }
            case .impact(let kind, _, let blocked):
                audio.play(kind == "lavaBomb" ? .ignite : .thump(0.5))
                if let pi = blocked {
                    say(kind == "lavaBomb" ? "Lavabrocken versperrt \(mission.rescuePoints[pi].name)." : "\(mission.rescuePoints[pi].name): Landeplatz von Trümmern blockiert.", seconds: 6)
                }
            case .struckByObject(let kind, let d):
                if kind != "lightning" { audio.play(.thump(0.9)) }
                shake = max(shake, min(16, CGFloat(d) / 1.5 + 4))
                if kind != "lightning" { say("Getroffen! \(Int(d.rounded())) % Haltbarkeit verloren.", seconds: 4) }
            case .padBlocked: break
            case .padCleared(let pi):
                say("\(mission.rescuePoints[pi].name) ist wieder frei.", seconds: 4)
            case .flowStarted(let fi):
                audio.play(.rumble)
                if mission.flowList[fi].kind == "avalanche" { say("Eine Lawine geht ab!", seconds: 4) }
            case .flowWarning(let fi, let pi):
                audio.play(.warn)
                let kind = mission.flowList[fi].kind
                if let pi = pi {
                    let name = mission.rescuePoints[pi].name
                    say(kind == "lava" ? "Lava nähert sich: \(name)!" : (kind == "surge" ? "Die Flutwelle nähert sich: \(name)!" : "Lawine auf Kurs: \(name)!"), seconds: 6)
                } else {
                    say(kind == "lava" ? "Ein Lavastrom setzt sich in Bewegung. Hole die Menschen weiter oben zuerst."
                        : (kind == "surge" ? "Der Damm bricht: Die Flutwelle läuft los. Hole die Menschen am Damm zuerst." : "Eine Lawine löst sich gleich. Wen sie erreicht, ist verloren."), seconds: 7)
                }
            case .flowScorched(let fi):
                shake = max(shake, 5)
                let kind = mission.flowList[fi].kind
                say(kind == "lava" ? "Hitze der Lava! Flieg höher." : (kind == "surge" ? "Die Flutwelle reißt am Hubschrauber! Flieg höher." : "Die Lawine reißt am Hubschrauber! Flieg höher."), seconds: 4)
            case .winchStarted:
                sayOnce("winch", "Seilwinde läuft: Halte den Hubschrauber ruhig über dem Vorsprung.", seconds: 5)
            case .winchSlipped:
                if clock - cableHint > 8 { cableHint = clock; say("Zu unruhig: Das Seil verliert die Person. Ruhig halten, nicht höher als das Seil.", seconds: 5) }
            case .iced:
                audio.play(.warn)
                say("Vereisung! Der Hubschrauber wird träge. Im Lager oder am Außenposten taut er ab.", seconds: 7)
            case .deiced:
                audio.play(.ding)
                say("Eisfrei.", seconds: 3)
            case .refueling:
                say("Außenposten: Der Hubschrauber tankt.", seconds: 4)
            case .shutterWarning(let pi, let si):
                if abs(mission.passageList[pi].shutterList[si].x - sim.heli.x) < 900 { audio.play(.pop) }
            case .shutterClosing(let pi, let si):
                if abs(mission.passageList[pi].shutterList[si].x - sim.heli.x) < 900 { audio.play(.thump(0.45)) }
            case .shutterCrush:
                audio.play(.crash)
                shake = max(shake, 16)
                say("Vom Shutter erwischt: Dieser Hubschrauber ist verloren.", seconds: 5)
            case .scored(let points, let combo):
                say(combo >= 2 ? "+\(points) Punkte · Kombo ×\(combo)" : "+\(points) Punkte", seconds: 2.5)
            case .comboBroken(let was):
                say("Kombo ×\(was) abgebrochen.", seconds: 3)
            case .flightBonus(let points, let people, let all):
                audio.play(.ding)
                say(all ? "Alle in einem Flug! +\(points) Punkte" : "Voller Flug mit \(people) Menschen: +\(points) Punkte", seconds: 4)
            case .obstacleHit(let kind, let d, let x, let y):
                let solid = d >= 100
                audio.play(solid ? .crash : .thump(0.8))
                shake = max(shake, solid ? 16 : 9)
                obstacles?.sparks(at: CGPoint(x: x, y: y), big: solid)
                let what: [String: String] = ["powerline": "Hochspannungsleitung", "crane": "Kran", "cablecar": "Seilbahn", "windmill": "Windrad"]
                if solid { say("\(what[kind] ?? "Hindernis") getroffen: Dieser Hubschrauber ist verloren.", seconds: 5) }
                else { say("Draht berührt, Funken! Die Haltbarkeit sinkt. Über oder unter den Leitungen fliegen.", seconds: 4) }
            case .weatherWarning(let kind, let seconds):
                audio.play(.warn)
                let s = Int(seconds.rounded())
                switch kind {
                case "gust": say("Böen im Anmarsch (\(s) s): Der Windsack zeigt die Richtung.", seconds: 6)
                case "windShift": say("Windwechsel in \(s) s: Der Windsack zeigt die neue Richtung.", seconds: 6)
                case "fog": say("Nebelbank zieht auf (\(s) s): Die Sicht wird schlecht, Gelände und Hindernisse im Kopf behalten.", seconds: 7)
                default: say("Gewitter zieht auf (\(s) s): Blitze im Anflug, auf die roten Kreise achten.", seconds: 7)
                }
            case .passageContact(let kind, let d):
                if d > 1 {
                    audio.play(.thump(0.7))
                    shake = max(shake, min(10, CGFloat(d) / 2 + 3))
                    sayOnce("contact-\(kind)-\(Int(clock / 4))", kind == "roof" ? "Decke berührt: tiefer fliegen." : "Gegen die Wand geflogen: Man kommt nur durch die Öffnung.", seconds: 3)
                }
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
        let engineOn = h.fuel > 0 && !crashed
        spool += ((engineOn ? 1 : 0) - spool) * CGFloat(min(1, dt * (engineOn ? 1.6 : 0.5)))
        heliSprite.update(facing: h.facing, engineOn: engineOn, spool: spool, time: clock)
        // Shadow on whatever is below: stays on the surface, fades and widens with height.
        syncDecks()
        let under = max(sim.live.maxSurface(from: h.x - 40, to: h.x + 40), mission.waterLevel(from: h.x - 40, to: h.x + 40, flood: sim.floodLevel))
        let alt = max(0, h.y - under)
        heliShadow.position = CGPoint(x: h.x, y: under + 1)
        heliShadow.size = CGSize(width: 150 + alt * 0.25, height: 16 + alt * 0.03)
        heliShadow.alpha = max(0, 0.42 - alt / 520) * (heliRoot.isHidden ? 0 : 1)

        syncLakes(dt: dt)
        syncFire(dt: dt)
        syncDrops()
        hazards?.sync(sim: sim, dt: dt, camX: cam.position.x)
        passages?.sync(sim: sim, dt: dt)
        obstacles?.sync(sim: sim, dt: dt)
        passageHints()
        atmosphere?.sync(sim: sim, heli: CGPoint(x: h.x - cam.position.x, y: h.y - cam.position.y), dt: dt)
        if sim.hz.tremor > 0, !gamePaused { shake = max(shake, CGFloat(sim.hz.tremor) * 5) }

        // Water
        let level = CGFloat(sim.floodLevel)
        water.isHidden = level < -20
        waveShape.isHidden = water.isHidden
        waveFoam.isHidden = water.isHidden
        let left = cam.position.x - 760
        water.position = CGPoint(x: cam.position.x, y: level - 8)
        waveTimer -= dt
        if waveTimer <= 0 {
        waveTimer = 1.0 / 30
        let wave = CGMutablePath()
        let foam = CGMutablePath()
        let t = CGFloat(clock)
        let amp: CGFloat = mission.flood.swell != nil ? 2.4 : 1
        var x = left
        var first = true
        while x <= left + 1520 {
            let y = level + amp * (3.2 * sin(x * 0.02 + t * 1.6) + 2.0 * sin(x * 0.045 - t * 2.3))
            if first { wave.move(to: CGPoint(x: x, y: y)); foam.move(to: CGPoint(x: x, y: y)); first = false }
            else { wave.addLine(to: CGPoint(x: x, y: y)); foam.addLine(to: CGPoint(x: x, y: y)) }
            x += 20
        }
        wave.addLine(to: CGPoint(x: left + 1520, y: level - 14))
        wave.addLine(to: CGPoint(x: left, y: level - 14))
        wave.closeSubpath()
        waveShape.path = wave
        waveFoam.path = foam
        }

        // People: feet always on the surface of their pad
        for p in sim.people {
            guard let node = personNodes[p.id] else { continue }
            let gy = CGFloat(sim.live.surfaceHeight(at: p.spotX))
            let fig = node.fig
            switch p.state {
            case .waiting:
                node.isHidden = false
                node.alpha = 1
                node.position = CGPoint(x: p.spotX, y: gy)
                fig.show("wave", phase: clock * 1.15 + Double(p.id) * 0.37)
                node.xScale = p.spotX < h.x ? 1 : -1
            case .boarding:
                node.isHidden = false
                let t = CGFloat(p.progress)
                node.position = CGPoint(x: p.spotX + (CGFloat(h.x) - CGFloat(p.spotX)) * t, y: gy)
                if t < 0.8 { fig.show("walk", phase: Double(t) * 3.6) } else { fig.show("climb", phase: Double((t - 0.8) / 0.2) * 0.99) }
                node.alpha = 1 - max(0, (t - 0.88) / 0.12)
                node.xScale = CGFloat(h.x) > CGFloat(p.spotX) ? 1 : -1
            case .hoisting:
                node.isHidden = false
                let t = CGFloat(p.progress)
                let hy = CGFloat(h.y) + 8
                node.position = CGPoint(x: p.spotX + (CGFloat(h.x) - CGFloat(p.spotX)) * t, y: gy + (hy - gy - 40) * t)
                node.alpha = 1
                fig.show("hoist", phase: 0)
                node.xScale = 1
            case .aboard, .injured:
                node.isHidden = true
            case .leaving:
                node.isHidden = false
                let t = CGFloat(p.progress)
                let targetX = CGFloat(mission.base.x - mission.base.width / 2 + 40 + CGFloat(p.id % 5) * 12)
                node.position = CGPoint(x: CGFloat(h.x) + (targetX - CGFloat(h.x)) * t, y: CGFloat(mission.baseSurface))
                node.alpha = 1
                fig.show("walk", phase: Double(t) * 3.6)
                node.xScale = targetX > CGFloat(h.x) ? 1 : -1
            case .rescued:
                node.isHidden = false
                let targetX = CGFloat(mission.base.x - mission.base.width / 2 + 40 + CGFloat(p.id % 5) * 12)
                node.position = CGPoint(x: targetX, y: CGFloat(mission.baseSurface))
                node.alpha = 1
                if p.id % 2 == 0 { fig.show("wave", phase: clock * 1.15 + Double(p.id) * 0.37) } else { fig.show("stand", phase: 0) }
                node.xScale = 1
            case .lost:
                node.isHidden = true
            }
        }
        for (i, m) in markers {
            let waiting = sim.people.contains { $0.pointIndex == i && ($0.state == .waiting || $0.state == .boarding || $0.state == .hoisting) }
            m.isHidden = !waiting || sim.isBlocked(i)
            beacons[i]?.isHidden = !waiting
        }

        // Winch cable
        if let w = sim.hz.winch, let p = sim.people.first(where: { $0.id == w.personID }), let node = personNodes[p.id] {
            let path = CGMutablePath()
            path.move(to: CGPoint(x: h.x, y: h.y + 6))
            path.addLine(to: CGPoint(x: node.position.x, y: node.position.y + 36))
            cable.path = path
            cable.strokeColor = w.steady ? SKColor(red: 0.95, green: 0.9, blue: 0.8, alpha: 1) : SKColor(red: 1, green: 0.5, blue: 0.3, alpha: 1)
            cable.isHidden = false
        } else {
            cable.isHidden = true
        }

        // Spray from stormy sea
        surfTimer -= dt
        if mission.flood.swell != nil, surfTimer <= 0, !gamePaused {
            surfTimer = 0.07
            let sx = cam.position.x + CGFloat.random(in: -680...680)
            let sp = SKSpriteNode(texture: Art.puff(), size: CGSize(width: 22, height: 22))
            sp.alpha = 0.55
            sp.position = CGPoint(x: sx, y: CGFloat(sim.floodLevel) + 4)
            sp.zPosition = 5.3
            addChild(sp)
            sp.run(.sequence([.group([.moveBy(x: CGFloat.random(in: -30...30) + CGFloat(sim.wind) * 0.2, y: CGFloat.random(in: 20...60), duration: 0.8), .fadeOut(withDuration: 0.8), .scale(to: 1.8, duration: 0.8)]), .removeFromParent()]))
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
        let surfaceUnder = sim.live.maxSurface(from: h.x - 40, to: h.x + 40)
        let waterUnder = mission.waterLevel(from: h.x - 40, to: h.x + 40, flood: sim.floodLevel)
        let floor = max(surfaceUnder, waterUnder)
        let above = h.y - floor
        if !h.onGround || above < 4, engineOn, above < 110, spawnTimer <= 0, !gamePaused {
            spawnTimer = 0.04
            let wet = waterUnder > surfaceUnder
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
        audio.spray = sim.dropping ? 1 : 0
        audio.fill = sim.filling ? 1 : 0
        fillSprayTimer -= dt
        if sim.filling, fillSprayTimer <= 0, !gamePaused {
            fillSprayTimer = 0.05
            spawnSpray(count: 3, strong: false, y: mission.waterLevel(from: h.x - 40, to: h.x + 40, flood: sim.floodLevel))
        }
        if h.fuel < mission.fuel.capacity * 0.2, h.fuel > 0, !lowFuelWarned, !h.onGround {
            lowFuelWarned = true
            audio.play(.warn)
            say("Treibstoff knapp. Zurück ins Lager!")
        }
        if h.fuel > mission.fuel.capacity * 0.5 { lowFuelWarned = false }
    }

    /// Swaying decks (ship, raft) with their marker and light.
    private func syncDecks() {
        for (i, p) in sim.live.rescuePoints.enumerated() where p.heave != nil {
            padNodes[i]?.position.y = CGFloat(p.top)
            markers[i]?.position.y = CGFloat(p.top + 110)
            beacons[i]?.position.y = CGFloat(p.top + 14)
        }
    }

    // MARK: Lakes, fire, water drops

    private func wavePath(x0: CGFloat, x1: CGFloat, level: CGFloat, t: CGFloat) -> (CGPath, CGPath) {
        let wave = CGMutablePath(), foam = CGMutablePath()
        var x = x0
        var first = true
        while x <= x1 {
            let y = level + 2.4 * sin(x * 0.025 + t * 1.2) + 1.6 * sin(x * 0.05 - t * 1.9)
            if first { wave.move(to: CGPoint(x: x, y: y)); foam.move(to: CGPoint(x: x, y: y)); first = false }
            else { wave.addLine(to: CGPoint(x: x, y: y)); foam.addLine(to: CGPoint(x: x, y: y)) }
            x += 20
        }
        wave.addLine(to: CGPoint(x: x1, y: level - 14))
        wave.addLine(to: CGPoint(x: x0, y: level - 14))
        wave.closeSubpath()
        return (wave, foam)
    }

    private func syncLakes(dt: Double) {
        lakeTimer -= dt
        guard lakeTimer <= 0 else { return }
        lakeTimer = 1.0 / 30
        let t = CGFloat(clock)
        for l in lakeNodes {
            let visible = abs(CGFloat((l.spec.x0 + l.spec.x1) / 2) - cam.position.x) < 1400
            l.body.isHidden = !visible; l.shape.isHidden = !visible; l.foam.isHidden = !visible
            guard visible else { continue }
            let (wave, foam) = wavePath(x0: CGFloat(l.spec.x0), x1: CGFloat(l.spec.x1), level: CGFloat(l.spec.level), t: t)
            l.shape.path = wave
            l.foam.path = foam
        }
    }

    private func makeFireNode(cell i: Int) -> FireNode {
        let x = CGFloat(sim.fire.center(of: i))
        let y = CGFloat(mission.surfaceHeight(at: Double(x)))

        let flame = SKEmitterNode()
        flame.particleTexture = Art.flame()
        flame.particleBirthRate = 0
        flame.particleLifetime = 0.9
        flame.particleLifetimeRange = 0.4
        flame.particlePositionRange = CGVector(dx: 34, dy: 4)
        flame.emissionAngle = .pi / 2
        flame.emissionAngleRange = 0.4
        flame.particleSpeed = 45
        flame.particleSpeedRange = 25
        flame.particleSize = CGSize(width: 30, height: 42)
        flame.particleScaleRange = 0.5
        flame.particleScaleSpeed = -0.45
        flame.particleAlpha = 0.55
        flame.particleAlphaSpeed = -1.0
        flame.particleBlendMode = .add
        flame.position = CGPoint(x: x, y: y + 2)
        flameLayer.addChild(flame)

        let smoke = SKEmitterNode()
        smoke.particleTexture = Art.puff()
        smoke.particleBirthRate = 0
        smoke.particleLifetime = 4.2
        smoke.particleLifetimeRange = 1.5
        smoke.particlePositionRange = CGVector(dx: 30, dy: 6)
        smoke.emissionAngle = .pi / 2
        smoke.emissionAngleRange = 0.5
        smoke.particleSpeed = 40
        smoke.particleSpeedRange = 18
        smoke.particleSize = CGSize(width: 36, height: 36)
        smoke.particleScaleSpeed = 0.5
        smoke.particleColor = SKColor(red: 0.20, green: 0.18, blue: 0.17, alpha: 1)
        smoke.particleColorBlendFactor = 1
        smoke.particleAlpha = 0.34
        smoke.particleAlphaSpeed = -0.075
        smoke.position = CGPoint(x: x, y: y + 30)
        smokeLayer.addChild(smoke)

        let scorch = SKSpriteNode(texture: Art.scorch(width: CGFloat(sim.fire.cellWidth) + 26))
        scorch.size = CGSize(width: CGFloat(sim.fire.cellWidth) + 26, height: 26)
        scorch.anchorPoint = CGPoint(x: 0.5, y: 0.2)
        scorch.position = CGPoint(x: x, y: y)
        scorch.zPosition = -7
        addChild(scorch)
        return FireNode(flame: flame, smoke: smoke, scorch: scorch)
    }

    private func syncFire(dt: Double) {
        guard mission.fire != nil else { return }
        let h = sim.heli
        var loud = 0.0
        for (i, c) in sim.fire.cells.enumerated() {
            guard c.burning || c.charred else { continue }
            let node = fireNodes[i] ?? { let n = makeFireNode(cell: i); fireNodes[i] = n; return n }()
            let near = abs(CGFloat(sim.fire.center(of: i)) - cam.position.x) < 900
            node.flame.isHidden = !near
            node.smoke.isHidden = !near
            node.scorch.isHidden = !near
            guard near else { continue }
            if c.burning {
                node.flame.particleBirthRate = CGFloat(26 * c.intensity)
                node.flame.particleScale = CGFloat(0.5 + 0.8 * c.intensity)
                node.smoke.particleBirthRate = c.intensity > 0.3 ? CGFloat(5 * c.intensity) : 0
                node.smoke.xAcceleration = CGFloat(sim.wind) * 0.25
                loud += c.intensity * max(0, 1 - abs(sim.fire.center(of: i) - h.x) / 700)
            } else {
                node.flame.particleBirthRate = 0
                node.smoke.particleBirthRate = 0
            }
            node.scorch.alpha = c.fuel <= 0 ? 0.95 : 0.55
        }
        audio.fire = Float(min(1, loud * 0.12))
        smokeSmooth += (CGFloat(sim.smoke) * 0.72 - smokeSmooth) * CGFloat(min(1, dt * 3))
        heatSmooth += (CGFloat(sim.heat) * 0.4 - heatSmooth) * CGFloat(min(1, dt * 6))
        smokeOverlay.alpha = smokeSmooth
        heatOverlay.alpha = heatSmooth
    }

    private func syncDrops() {
        var alive = Set<Int>()
        for d in sim.drops {
            alive.insert(d.id)
            let n = dropNodes[d.id] ?? {
                let s = SKSpriteNode(texture: Art.waterDrop(), size: CGSize(width: 6, height: 10))
                s.zPosition = 11
                effects.addChild(s)
                dropNodes[d.id] = s
                return s
            }()
            n.position = CGPoint(x: d.x, y: d.y)
            n.zRotation = atan2(CGFloat(d.vy), CGFloat(d.vx)) - .pi / 2
        }
        for (id, n) in dropNodes where !alive.contains(id) {
            dropNodes[id] = nil
            let p = n.position
            n.removeFromParent()
            // Where it hit: a puff of steam over flames or damp ground, a few droplets otherwise.
            let burning = sim.fire.index(at: Double(p.x)).map { sim.fire.cells[$0].wet > 0 || sim.fire.cells[$0].burning } ?? false
            let s = SKSpriteNode(texture: Art.puff())
            let size: CGFloat = burning ? 34 : 14
            s.size = CGSize(width: size, height: size)
            s.alpha = burning ? 0.5 : 0.55
            s.position = p
            effects.addChild(s)
            s.run(.sequence([
                .group([.moveBy(x: CGFloat.random(in: -16...16), y: burning ? 46 : 14, duration: 0.7),
                        .fadeOut(withDuration: 0.7), .scale(to: burning ? 2.2 : 1.6, duration: 0.7)]),
                .removeFromParent()]))
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

    private func spawnSpray(count: Int, strong: Bool, y: Double? = nil) {
        let h = sim.heli
        for _ in 0..<max(4, count) {
            let p = SKSpriteNode(texture: Art.puff())
            p.size = CGSize(width: 18, height: 18)
            p.alpha = 0.7
            p.position = CGPoint(x: h.x + Double.random(in: -40...40), y: (y ?? sim.floodLevel) + 4)
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
        snap.score = sim.livePoints
        snap.combo = sim.tally.combo
        snap.helicoptersTotal = mission.isPractice ? -1 : mission.helicopters
        snap.wind = sim.wind
        snap.floodLevel = sim.floodLevel
        snap.heliX = h.x
        snap.worldWidth = mission.world.width
        snap.baseX = mission.base.x
        snap.water = h.water / mission.tankSpec.capacity
        snap.filling = sim.filling
        snap.smoke = sim.smoke
        snap.heat = sim.heat
        snap.ice = mission.icing == nil ? -1 : sim.ice
        snap.swelter = mission.heatwave == nil ? -1 : sim.swelter
        snap.fires = sim.fire.cells.indices.filter { sim.fire.cells[$0].burning }.map { sim.fire.center(of: $0) }
        snap.points = mission.rescuePoints.enumerated().map { i, p in
            let waiting = sim.people.filter { $0.pointIndex == i && $0.state == .waiting }.count
            return MiniMapPoint(x: p.x, waiting: waiting,
                                endangered: sim.floodLevel > p.top - 35 || sim.fireExposure[i] > 0.5)
        }
        snap.spans = mission.flowList.indices.compactMap { i in sim.hz.flows[i].span.map { MiniMapSpan(lo: $0.lo, hi: $0.hi, lava: mission.flowList[i].kind == "lava") } }
        snap.outposts = mission.outpostList.map(\.x)
        if let w = sim.hz.winch { snap.winch = w.progress; snap.winchSteady = w.steady } else { snap.winch = -1 }
        snap.messages = messages.map { $0.text }
        if case .crashed = sim.phase { snap.crashed = true }
        onHUD?(snap)
    }
}
