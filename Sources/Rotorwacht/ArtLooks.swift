import SpriteKit
import CoreGraphics
import RotorwachtCore

/// Colours and options of a landscape style (`Mission.look`), plus the pictures only the newer Einsätze need.
struct Look {
    var sky: [(CGFloat, UInt32, CGFloat)]
    var glow: (x: CGFloat, y: CGFloat, r: CGFloat, hex: UInt32, a: CGFloat)?
    var stars = false
    var far: [UInt32]
    var mist: UInt32
    var hill: [(CGFloat, UInt32, CGFloat)]
    var hillTrees = true
    var ground: [(CGFloat, UInt32, CGFloat)]
    var edgeDark: UInt32
    var edgeLight: UInt32
    var edgeWide: CGFloat = 9
    var trees = true
    var town = false

    static let valley = Look(
        sky: [(0, 0x5e7388, 1), (0.45, 0x93a6b4, 1), (0.78, 0xcdd0cb, 1), (1, 0xe9dcc6, 1)],
        glow: (0.72, 0.30, 300, 0xfff0cf, 0.55),
        far: [0xa2b0bc, 0x8d9eab], mist: 0xcfd3d0,
        hill: [(0, 0x5c7466, 1), (0.6, 0x62806c, 1), (1, 0x8fa092, 1)],
        ground: [(0, 0x82744f, 1), (0.55, 0x6a5841, 1), (1, 0x3b2f27, 1)],
        edgeDark: 0x4f6334, edgeLight: 0x8fa05a)

    static func of(_ m: Mission) -> Look {
        var l: Look
        switch m.look ?? "valley" {
        case "coast":
            l = valley
            l.far = [0x4b5662, 0x3b4651]; l.mist = 0x59636d
            l.hill = [(0, 0x3d4a50, 1), (0.6, 0x45545a, 1), (1, 0x5a6a70, 1)]
            l.hillTrees = false
            l.ground = [(0, 0x77706a, 1), (0.55, 0x5a5550, 1), (1, 0x2d2a28, 1)]
            l.edgeDark = 0x4d5a4a; l.edgeLight = 0x7d8c6d; l.edgeWide = 7
            l.trees = false
        case "town":
            l = valley
            l.sky = [(0, 0x7d746c, 1), (0.5, 0xb59f8a, 1), (0.8, 0xd9c19c, 1), (1, 0xe8d3ae, 1)]
            l.glow = (0.6, 0.28, 320, 0xffe2b0, 0.5)
            l.far = [0xb59f8f, 0x9d8a7c]; l.mist = 0xdcc9b0
            l.hill = [(0, 0x8b7a6c, 1), (0.6, 0x9a8878, 1), (1, 0xb6a48f, 1)]
            l.hillTrees = false
            l.ground = [(0, 0xd6c3a2, 1), (0.5, 0xc2ab88, 1), (1, 0x8f7b60, 1)]
            l.edgeDark = 0x4a3f36; l.edgeLight = 0x8d8072; l.edgeWide = 7
            l.trees = false; l.town = true
        case "volcano":
            l = valley
            l.sky = [(0, 0x2f2523, 1), (0.45, 0x5a3d33, 1), (0.8, 0x93603f, 1), (1, 0xc98a52, 1)]
            l.glow = (0.34, 0.2, 380, 0xff8a3a, 0.5)
            l.far = [0x4a3a36, 0x372b29]; l.mist = 0x7c5a44
            l.hill = [(0, 0x2f2724, 1), (0.6, 0x3a2f2b, 1), (1, 0x5a4338, 1)]
            l.hillTrees = false
            l.ground = [(0, 0x5b4d46, 1), (0.5, 0x3a312d, 1), (1, 0x171312, 1)]
            l.edgeDark = 0x211b19; l.edgeLight = 0x6d4a35; l.edgeWide = 8
            l.trees = false
        case "alpine":
            l = valley
            l.sky = [(0, 0x6f8db0, 1), (0.5, 0xa9c2d8, 1), (0.8, 0xdbe6ee, 1), (1, 0xeef2f4, 1)]
            l.glow = (0.7, 0.3, 280, 0xffffff, 0.5)
            l.far = [0xb8c7d6, 0x9fb1c3]; l.mist = 0xe8eef2
            l.hill = [(0, 0x6f7f91, 1), (0.6, 0x8798aa, 1), (1, 0xb4c2d0, 1)]
            l.hillTrees = false
            l.ground = [(0, 0x9aa1a9, 1), (0.55, 0x6f757e, 1), (1, 0x3a3e45, 1)]
            l.edgeDark = 0xc9d3dc; l.edgeLight = 0xfafcfd; l.edgeWide = 10
            l.trees = false
        default:
            l = valley
        }
        switch m.atmosphere?.sky {
        case "night":
            l.sky = [(0, 0x070b14, 1), (0.5, 0x10192a, 1), (0.85, 0x1b2638, 1), (1, 0x273449, 1)]
            l.glow = (0.8, 0.3, 160, 0x9fb2d0, 0.18)
            l.stars = true
            l.far = [0x2e3d52, 0x25344a]; l.mist = 0x3a4d66
            l.hill = [(0, 0x1f2d3b, 1), (0.6, 0x2c3c4d, 1), (1, 0x3a4c5e, 1)]
        default: break
        }
        return l
    }

    // Stored `glow` is a tuple with named parts; Art.sky reads .x .y .r .hex .a
}

extension Art {
    /// Plaster walls with rows of windows over the blocks of an old town (terrain above street level).
    static func drawTownFacades(_ ctx: CGContext, mission: Mission, x0: CGFloat, w: CGFloat, yMin: CGFloat) {
        let street = mission.terrain.map(\.y).min() ?? 0
        var gx = (x0 / 34).rounded(.down) * 34
        while gx < x0 + w + 34 {
            let wx = gx + 17
            let top = CGFloat(mission.groundHeight(at: Double(wx)))
            let h = top - CGFloat(street)
            if h > 120 {
                var rng = RNG(UInt64(abs(gx / 34)) &+ 5)
                var y = CGFloat(street) + 34
                while y < top - 38 {
                    let inside = mission.groundHeight(at: Double(wx - 12)) > Double(y + 30) && mission.groundHeight(at: Double(wx + 12)) > Double(y + 30)
                    if inside, rng.next() > 0.12 {
                        let lit = rng.next() > 0.8
                        let rect = CGRect(x: wx - x0 - 7, y: y - yMin, width: 14, height: 22)
                        fillVertical(ctx, rect, lit ? [(0, 0xf3d88a, 1), (1, 0xd9a64e, 1)] : [(0, 0x7a8c96, 1), (1, 0x4a5c68, 1)])
                        ctx.setStrokeColor(c(0xfffdf9, 0.7)); ctx.setLineWidth(1.2); ctx.stroke(rect)
                    }
                    y += 46
                }
            }
            gx += 34
        }
        // Roof lines: dark cap on every block top.
        ctx.setFillColor(c(0x6a4a3a, 0.9))
        var x: CGFloat = -2
        while x <= w + 6 {
            let t = CGFloat(mission.groundHeight(at: Double(x + x0))), tn = CGFloat(mission.groundHeight(at: Double(x + x0 + 6)))
            if t > CGFloat(street) + 60, abs(t - tn) < 2 { ctx.fill(CGRect(x: x, y: t - yMin - 10, width: 6, height: 10)) }
            x += 6
        }
    }

    // MARK: buildings of the newer Einsätze

    /// Fishing boat with a flat deck (landing surface at the top edge of the image).
    static func boat(width: CGFloat, top: CGFloat) -> SKTexture {
        let size = CGSize(width: width + 60, height: top + 30)
        return texture(size) { ctx in
            let x0: CGFloat = 30, h = size.height
            // Hull
            ctx.setFillColor(c(0x2f4a5c))
            ctx.move(to: CGPoint(x: x0 - 22, y: h - 8)); ctx.addLine(to: CGPoint(x: x0 + width + 22, y: h - 8))
            ctx.addLine(to: CGPoint(x: x0 + width - 14, y: 4)); ctx.addLine(to: CGPoint(x: x0 + 20, y: 4)); ctx.closePath(); ctx.fillPath()
            ctx.setFillColor(c(0xc75d3b)); ctx.fill(CGRect(x: x0 - 14, y: h - 22, width: width + 28, height: 8))
            ctx.setFillColor(c(0xe8e4dc)); ctx.fill(CGRect(x: x0 - 20, y: h - 14, width: width + 40, height: 6))
            // Deck
            ctx.setFillColor(c(0x8a7a64)); ctx.fill(CGRect(x: x0 - 20, y: h - 8, width: width + 40, height: 8))
            ctx.setFillColor(c(0xe9c85a, 0.9)); ctx.fill(CGRect(x: x0 + 10, y: h - 3.5, width: width - 20, height: 1.5))
            // Wheelhouse is to the side, outside the landing area: a mast with a lamp.
            ctx.setFillColor(c(0x4a4340)); ctx.fill(CGRect(x: x0 + width + 6, y: h - 8, width: 3, height: 26))
            softCircle(ctx, CGPoint(x: x0 + width + 7, y: h + 14), 14, 0xffd9a0, 0.8)
            // Lamp row on the deck edge
            for i in 0..<5 {
                softCircle(ctx, CGPoint(x: x0 + 8 + CGFloat(i) * (width - 16) / 4, y: h - 5), 8, 0xff9b4a, 0.85)
            }
        }
    }

    /// Lighthouse: striped shaft under a round landing gallery at the top edge of the image.
    static func lighthouse(width: CGFloat, top: CGFloat, seed: UInt64) -> SKTexture {
        let below: CGFloat = 60
        let h = top + below
        let size = CGSize(width: width + 28, height: h)
        return texture(size) { ctx in
            let cx = size.width / 2
            let shaftBottom = width * 0.46, shaftTop = width * 0.30
            var y: CGFloat = 0
            var k = 0
            while y < h - 24 {
                let y2 = min(h - 24, y + 36)
                let t0 = y / h, t1 = y2 / h
                let w0 = shaftBottom + (shaftTop - shaftBottom) * t0, w1 = shaftBottom + (shaftTop - shaftBottom) * t1
                ctx.setFillColor(c(k % 2 == 0 ? 0xf1ece2 : 0xb94f30))
                ctx.move(to: CGPoint(x: cx - w0 / 2, y: y)); ctx.addLine(to: CGPoint(x: cx + w0 / 2, y: y))
                ctx.addLine(to: CGPoint(x: cx + w1 / 2, y: y2)); ctx.addLine(to: CGPoint(x: cx - w1 / 2, y: y2)); ctx.closePath(); ctx.fillPath()
                y = y2; k += 1
            }
            ctx.setFillColor(c(0x57544f)); ctx.fill(CGRect(x: cx - width / 2, y: h - 22, width: width, height: 18))
            ctx.setFillColor(c(0x8a867f)); ctx.fill(CGRect(x: cx - width / 2, y: h - 5, width: width, height: 5))
            ctx.setFillColor(c(0xe9c85a, 0.9)); ctx.fill(CGRect(x: cx - width / 2 + 12, y: h - 3.5, width: width - 24, height: 1.6))
            softCircle(ctx, CGPoint(x: cx + width / 2 - 6, y: h + 2), 14, 0xffe6b0, 0.9)
        }
    }

    /// Flat roof of a town house: only the landing slab, the walls are the terrain.
    static func rooftopPad(width: CGFloat) -> SKTexture {
        texture(CGSize(width: width + 20, height: 26)) { ctx in
            ctx.setFillColor(c(0x5d5a55)); ctx.fill(CGRect(x: 0, y: 8, width: width + 20, height: 10))
            ctx.setFillColor(c(0x8a867f)); ctx.fill(CGRect(x: 0, y: 14, width: width + 20, height: 4))
            ctx.setFillColor(c(0xe9c85a, 0.95))
            var dx: CGFloat = 14
            while dx < width + 4 { ctx.fill(CGRect(x: dx, y: 15, width: 14, height: 2)); dx += 24 }
            ctx.setFillColor(c(0xc75d3b, 0.9)); ctx.fill(CGRect(x: 0, y: 8, width: width + 20, height: 3))
        }
    }

    /// Small refuelling post: pad with pump and a sign. Anchored at bottom centre on the ground.
    static func outpost(width: CGFloat) -> SKTexture {
        let size = CGSize(width: width + 60, height: 120)
        return texture(size) { ctx in
            let x0: CGFloat = 30
            fillVertical(ctx, CGRect(x: x0, y: 0, width: width, height: 6), [(0, 0x77746e, 1), (1, 0x57544f, 1)])
            ctx.setFillColor(c(0xe9c85a)); ctx.fill(CGRect(x: x0 + width * 0.25, y: 3.5, width: width * 0.5, height: 1.6))
            // Pump column
            fillVertical(ctx, CGRect(x: x0 + width - 26, y: 6, width: 18, height: 40), [(0, 0xe8e4dc, 1), (1, 0xb4b0a6, 1)])
            ctx.setFillColor(c(0xc75d3b)); ctx.fill(CGRect(x: x0 + width - 26, y: 28, width: 18, height: 6))
            ctx.setStrokeColor(c(0x3a3735)); ctx.setLineWidth(2)
            ctx.move(to: CGPoint(x: x0 + width - 8, y: 36)); ctx.addLine(to: CGPoint(x: x0 + width + 2, y: 30)); ctx.addLine(to: CGPoint(x: x0 + width + 2, y: 12)); ctx.strokePath()
            // Sign pole with lamp
            ctx.setFillColor(c(0x57544f)); ctx.fill(CGRect(x: x0 + 10, y: 6, width: 3, height: 80))
            ctx.setFillColor(c(0xc75d3b)); ctx.fill(CGRect(x: x0 + 2, y: 74, width: 38, height: 16))
            ctx.setFillColor(c(0xfffdf9)); ctx.fill(CGRect(x: x0 + 6, y: 80, width: 30, height: 3))
            softCircle(ctx, CGPoint(x: x0 + 11, y: 96), 14, 0xffe6b0, 0.7)
            for i in 0...5 {
                softCircle(ctx, CGPoint(x: x0 + 6 + CGFloat(i) * (width - 12) / 5, y: 8), 6, 0xff9b4a, 0.85)
            }
        }
    }

    // MARK: effects of the newer hazards

    /// A lump of debris or rock, irregular.
    private static let cached_rock: SKTexture = make_rock()
    static func rock() -> SKTexture { cached_rock }
    private static func make_rock() -> SKTexture {
        texture(CGSize(width: 40, height: 40)) { ctx in
            ctx.setFillColor(c(0x6a645c))
            let pts: [(CGFloat, CGFloat)] = [(6, 14), (14, 4), (28, 6), (36, 18), (30, 34), (14, 36), (4, 26)]
            ctx.move(to: CGPoint(x: pts[0].0, y: pts[0].1))
            for p in pts.dropFirst() { ctx.addLine(to: CGPoint(x: p.0, y: p.1)) }
            ctx.closePath(); ctx.fillPath()
            ctx.setFillColor(c(0x8c857b)); ctx.fillEllipse(in: CGRect(x: 10, y: 18, width: 14, height: 12))
            ctx.setFillColor(c(0x3f3a35, 0.7)); ctx.fillEllipse(in: CGRect(x: 18, y: 6, width: 14, height: 10))
        }
    }

    /// Glowing lava bomb.
    private static let cached_lavaBomb: SKTexture = make_lavaBomb()
    static func lavaBomb() -> SKTexture { cached_lavaBomb }
    private static func make_lavaBomb() -> SKTexture {
        texture(CGSize(width: 48, height: 48)) { ctx in
            softCircle(ctx, CGPoint(x: 24, y: 24), 24, 0xff6a1a, 0.55)
            ctx.setFillColor(c(0x3a1a10)); ctx.fillEllipse(in: CGRect(x: 14, y: 14, width: 20, height: 20))
            softCircle(ctx, CGPoint(x: 24, y: 24), 12, 0xff9a2a, 0.9)
            softCircle(ctx, CGPoint(x: 22, y: 26), 6, 0xffe08a, 0.9)
        }
    }

    /// Pile of rubble on the ground, anchored at the bottom centre.
    private static let cached_rubble: SKTexture = make_rubble()
    static func rubble() -> SKTexture { cached_rubble }
    private static func make_rubble() -> SKTexture {
        texture(CGSize(width: 90, height: 34)) { ctx in
            var rng = RNG(3)
            for i in 0..<14 {
                let r = CGFloat(rng.range(5, 12))
                let x = CGFloat(rng.range(12, 78)), y = CGFloat(rng.range(2, 16)) + (abs(x - 45) < 20 ? 6 : 0)
                ctx.setFillColor(c([0x6a645c, 0x857e74, 0x514c46, 0x9a9287][i % 4]))
                ctx.fillEllipse(in: CGRect(x: x - r, y: y, width: r * 2, height: r * 1.3))
            }
        }
    }

    /// One bolt of lightning from the top (y = 1) to the ground (y = 0): jagged, with glow. Width 140.
    static func bolt(height: CGFloat, seed: UInt64) -> SKTexture {
        texture(CGSize(width: 140, height: height)) { ctx in
            var rng = RNG(seed)
            var x: CGFloat = 70, y = height
            var pts = [CGPoint(x: x, y: y)]
            while y > 0 {
                y = max(0, y - CGFloat(rng.range(28, 60)))
                x = min(120, max(20, x + CGFloat(rng.range(-26, 26))))
                pts.append(CGPoint(x: y == 0 ? 70 : x, y: y))
            }
            for (lw, a) in [(9.0, 0.18), (4.5, 0.4), (2.0, 1.0)] as [(CGFloat, CGFloat)] {
                ctx.setStrokeColor(c(lw > 3 ? 0xbcd2ff : 0xffffff, a)); ctx.setLineWidth(lw); ctx.setLineJoin(.round)
                ctx.move(to: pts[0]); for p in pts.dropFirst() { ctx.addLine(to: p) }
                ctx.strokePath()
            }
        }
    }

    /// Warning beam where lightning will strike: dashed, tall, 24 wide.
    private static let cached_beam: SKTexture = make_beam()
    static func warnBeam() -> SKTexture { cached_beam }
    private static func make_beam() -> SKTexture {
        texture(CGSize(width: 24, height: 640)) { ctx in
            fillVertical(ctx, CGRect(x: 0, y: 0, width: 24, height: 640), [(0, 0xff5a3a, 0.65), (1, 0xff5a3a, 0.0)])
            ctx.setBlendMode(.destinationOut)
            var y: CGFloat = 0
            while y < 640 { ctx.fill(CGRect(x: 0, y: y + 18, width: 24, height: 12)); y += 30 }
        }
    }

    /// Darkness with a lit cone: an 800 x 800 picture shown at 4x, helicopter at the centre, cone pointing to the right (+x),
    /// opening 38 degrees, small glow around the helicopter. Rotated and placed by the scene.
    private static let cached_night: SKTexture = make_night()
    static func nightCone() -> SKTexture { cached_night }
    private static func make_night() -> SKTexture {
        let s: CGFloat = 800
        return texture(CGSize(width: s, height: s)) { ctx in
            ctx.setFillColor(c(0x0a1220, 0.60)); ctx.fill(CGRect(x: 0, y: 0, width: s, height: s))
            ctx.setBlendMode(.destinationOut)
            let center = CGPoint(x: s / 2, y: s / 2)
            // Soft glow around the helicopter.
            let glow = gradient([(0, 0x000000, 0.95), (0.5, 0x000000, 0.55), (1, 0x000000, 0)])
            ctx.drawRadialGradient(glow, startCenter: center, startRadius: 0, endCenter: center, endRadius: 70, options: [])
            // Cone.
            ctx.saveGState()
            let half: CGFloat = 0.34
            let path = CGMutablePath()
            path.move(to: center)
            path.addArc(center: center, radius: 195, startAngle: -half, endAngle: half, clockwise: false)
            path.closeSubpath()
            ctx.addPath(path); ctx.clip()
            let g = gradient([(0, 0x000000, 0.95), (0.55, 0x000000, 0.7), (1, 0x000000, 0.0)])
            ctx.drawRadialGradient(g, startCenter: center, startRadius: 5, endCenter: center, endRadius: 195, options: [])
            ctx.restoreGState()
        }
    }

    /// Beacon glow over a rescue point in the dark.
    private static let cached_beacon: SKTexture = make_beacon()
    static func beaconGlow() -> SKTexture { cached_beacon }
    private static func make_beacon() -> SKTexture {
        texture(CGSize(width: 120, height: 120)) { ctx in
            softCircle(ctx, CGPoint(x: 60, y: 60), 60, 0xffb070, 0.55)
            softCircle(ctx, CGPoint(x: 60, y: 60), 14, 0xfff0d0, 0.9)
        }
    }

    /// A speck of ash or snow.
    private static let cached_fleck: SKTexture = make_fleck()
    static func fleck() -> SKTexture { cached_fleck }
    private static func make_fleck() -> SKTexture {
        texture(CGSize(width: 8, height: 8)) { ctx in softCircle(ctx, CGPoint(x: 4, y: 4), 4, 0xffffff, 1) }
    }

    /// Flow surface (lava or avalanche): a tileable strip 64 x 48.
    static func flowStrip(lava: Bool) -> SKTexture {
        texture(CGSize(width: 64, height: 48)) { ctx in
            if lava {
                fillVertical(ctx, CGRect(x: 0, y: 0, width: 64, height: 48), [(0, 0xffd27a, 1), (0.25, 0xff8a1f, 1), (1, 0x8a2a0e, 1)])
                ctx.setFillColor(c(0x2a1410, 0.55))
                for (x, y, w) in [(6, 30, 20), (36, 20, 18), (18, 8, 16)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: 7))
                }
            } else {
                fillVertical(ctx, CGRect(x: 0, y: 0, width: 64, height: 48), [(0, 0xffffff, 1), (0.5, 0xe6eef5, 1), (1, 0xb9c8d6, 1)])
                ctx.setFillColor(c(0xffffff, 0.6))
                for (x, y, w) in [(4, 34, 22), (34, 24, 24), (14, 10, 18)] as [(CGFloat, CGFloat, CGFloat)] {
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: w, height: 8))
                }
            }
        }
    }
}
