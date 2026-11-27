import SpriteKit
import AppKit
import RotorwachtCore

/// Loads the pre-rendered 3D images (made with Blender, see art/ and scripts/render-art.sh).
enum Render {
    /// 16 points per metre: the helicopter and the people are modelled in metres.
    static let pt: CGFloat = 16
    private static var cache: [String: SKTexture] = [:]

    static func texture(_ folder: String, _ name: String) -> SKTexture? {
        let key = folder + "/" + name
        if let t = cache[key] { return t }
        guard let u = Res.url(name, "png", in: "Renders/" + folder), let img = NSImage(contentsOf: u),
              let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let t = SKTexture(cgImage: cg)
        t.filteringMode = .linear
        cache[key] = t
        return t
    }

    static func json(_ folder: String, _ name: String) -> [String: Any]? {
        guard let u = Res.url(name, "json", in: "Renders/" + folder), let d = try? Data(contentsOf: u),
              let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return nil }
        return o
    }

    /// Size and anchor of the pad sprites (`pad-<mission>-<point>`).
    struct PadMeta { var w: CGFloat; var h: CGFloat; var u: CGFloat; var v: CGFloat }
    static let padMeta: [String: PadMeta] = {
        guard let j = json("pads", "pads") else { return [:] }
        var out: [String: PadMeta] = [:]
        for (k, v) in j {
            if let d = v as? [String: Double] { out[k] = PadMeta(w: d["w"] ?? 0, h: d["h"] ?? 0, u: d["u"] ?? 0.5, v: d["v"] ?? 0) }
        }
        return out
    }()

    /// A sprite whose anchor is the middle of the landing surface; at the pad's (x, top) the surface lies exactly on `top`.
    static func padSprite(_ name: String) -> SKSpriteNode? {
        guard let m = padMeta[name], let t = texture("pads", name) else { return nil }
        let n = SKSpriteNode(texture: t, size: CGSize(width: m.w, height: m.h))
        n.anchorPoint = CGPoint(x: m.u, y: m.v)
        return n
    }
}

/// The rescue helicopter: layered renders (body, rotor, blur discs) chosen by viewing angle, plus blinking lights.
final class HeliSprite: SKNode {
    static let yaws = [-90, -70, -45, -22, 0, 22, 45, 70, 90]
    private let meta = Render.json("heli", "anchors") ?? [:]
    private var frameSize = CGSize(width: 13.2 * Render.pt, height: 5.0 * Render.pt)
    private var frames: [[String: [CGFloat]]] = []
    private var tex: [String: [SKTexture]] = [:]
    private let body = SKSpriteNode(), rotor = SKSpriteNode(), rotorBlur = SKSpriteNode(), tailBlur = SKSpriteNode()
    private var glows: [String: SKSpriteNode] = [:]
    private var current = -1
    private(set) var available = false

    override init() {
        super.init()
        if let w = meta["frameW"] as? Double, let h = meta["frameH"] as? Double {
            frameSize = CGSize(width: w * Render.pt, height: h * Render.pt)
        }
        let fr = meta["frames"] as? [String: [String: [Double]]] ?? [:]
        for y in Self.yaws {
            let key = String(format: "%+03d", y)
            frames.append((fr[key] ?? [:]).mapValues { $0.map { CGFloat($0) } })
        }
        for layer in ["body", "rotor", "rotorblur", "tailblur"] {
            tex[layer] = Self.yaws.compactMap { Render.texture("heli", "heli-\(layer)-" + String(format: "%+03d", $0)) }
        }
        available = tex["body"]?.count == Self.yaws.count && frames.count == Self.yaws.count
        for s in [body, rotor, rotorBlur, tailBlur] {
            s.size = frameSize
            addChild(s)
        }
        body.zPosition = 0; rotor.zPosition = 0.2; rotorBlur.zPosition = 0.3; tailBlur.zPosition = 0.1
        let colors: [(String, SKColor, CGFloat)] = [
            ("navPort", SKColor(red: 1, green: 0.2, blue: 0.15, alpha: 1), 6), ("navStar", SKColor(red: 0.2, green: 1, blue: 0.4, alpha: 1), 6),
            ("tailLight", .white, 5), ("strobe", SKColor(red: 1, green: 0.25, blue: 0.2, alpha: 1), 12), ("strobeTop", .white, 10)]
        for (k, c, r) in colors {
            let g = SKSpriteNode(texture: Art.beaconGlow(), size: CGSize(width: r * 2, height: r * 2))
            g.color = c; g.colorBlendFactor = 1; g.blendMode = .add; g.zPosition = 0.5
            addChild(g); glows[k] = g
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    /// Position (relative to the skid contact point) of a named point in the current frame.
    func point(_ name: String) -> CGPoint? {
        guard current >= 0, let c = frames[current]["contact"], let p = frames[current][name] else { return nil }
        return CGPoint(x: (p[0] - c[0]) * frameSize.width, y: (p[1] - c[1]) * frameSize.height)
    }

    /// facing: -1 (left) ... +1 (right), 0 = towards the player.
    func update(facing: Double, engineOn: Bool, spool: CGFloat, time: Double) {
        guard available else { return }
        let want = facing * 90
        var best = 0
        for (i, y) in Self.yaws.enumerated() where abs(Double(y) - want) < abs(Double(Self.yaws[best]) - want) { best = i }
        if best != current {
            current = best
            body.texture = tex["body"]![best]; rotor.texture = tex["rotor"]![best]
            rotorBlur.texture = tex["rotorblur"]![best]; tailBlur.texture = tex["tailblur"]![best]
            if let c = frames[best]["contact"] {
                let a = CGPoint(x: c[0], y: c[1])
                for s in [body, rotor, rotorBlur, tailBlur] { s.anchorPoint = a }
            }
        }
        let yaw = Self.yaws[best]
        rotor.alpha = 1 - spool
        rotorBlur.alpha = spool * (0.82 + 0.18 * CGFloat(sin(time * 31)))
        tailBlur.alpha = spool
        for (k, g) in glows {
            guard let p = point(k) else { g.isHidden = true; continue }
            g.position = p
            var a: CGFloat = 0.7
            switch k {
            case "navPort": g.isHidden = yaw > 30
            case "navStar": g.isHidden = yaw < -30
            case "tailLight": g.isHidden = abs(yaw) < 40
            case "strobe": g.isHidden = false; a = sin(time * 7.5) > 0.82 ? 1 : 0
            default: g.isHidden = false; a = (sin(time * 7.5 + 1.6) > 0.85) ? 1 : 0
            }
            g.alpha = a * (engineOn ? 1 : 0.15)
        }
    }
}

/// One person: frame animation from the rendered figure types (feet on the node's origin).
final class FigureSprite: SKNode {
    static let types = ["helfer", "frau", "kind", "opa", "wanderer"]
    static let counts = ["wave": 8, "stand": 1, "walk": 8, "climb": 4, "hoist": 1]
    private let sprite = SKSpriteNode()
    private let type: String
    private var shown = ""
    /// People are drawn larger than the helicopter's scale, so they can be seen well (looks only, no rule uses it).
    static let scale: CGFloat = 1.3
    private let size = CGSize(width: 1.9 * Render.pt * FigureSprite.scale, height: 2.5 * Render.pt * FigureSprite.scale)
    private let footV: CGFloat = 0.02

    init(id: Int) {
        type = Self.types[id % Self.types.count]
        super.init()
        sprite.size = size
        sprite.anchorPoint = CGPoint(x: 0.5, y: footV)
        addChild(sprite)
    }
    required init?(coder: NSCoder) { fatalError() }

    /// `phase` 0...1 selects the frame inside the animation.
    func show(_ anim: String, phase: Double) {
        let n = Self.counts[anim] ?? 1
        let i = min(n - 1, max(0, Int(phase.truncatingRemainder(dividingBy: 1) * Double(n))))
        let name = "\(type)-\(anim)-\(i)"
        if name == shown { return }
        shown = name
        if let t = Render.texture("people", name) { sprite.texture = t }
    }
}
