import SpriteKit
import CoreGraphics
import RotorwachtCore

/// All graphics are drawn from code (shapes and gradients) at 2x resolution. No image files, nothing to license.
enum Art {
    static let scale: CGFloat = 2

    // MARK: helpers

    static func c(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
        CGColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255,
                blue: CGFloat(hex & 0xff) / 255, alpha: a)
    }

    static func texture(_ size: CGSize, _ draw: (CGContext) -> Void) -> SKTexture {
        let w = max(1, Int((size.width * scale).rounded(.up))), h = max(1, Int((size.height * scale).rounded(.up)))
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.setAllowsAntialiasing(true)
        ctx.interpolationQuality = .high
        draw(ctx)
        let t = SKTexture(cgImage: ctx.makeImage()!)
        t.filteringMode = .linear
        return t
    }

    static func gradient(_ stops: [(CGFloat, UInt32, CGFloat)]) -> CGGradient {
        let colors = stops.map { c($0.1, $0.2) } as CFArray
        let locs = stops.map { $0.0 }
        return CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: locs)!
    }

    /// Fills the current clip with a vertical gradient (top → bottom of `rect`).
    static func fillVertical(_ ctx: CGContext, _ rect: CGRect, _ stops: [(CGFloat, UInt32, CGFloat)]) {
        ctx.saveGState()
        ctx.clip(to: rect)
        ctx.drawLinearGradient(gradient(stops), start: CGPoint(x: 0, y: rect.maxY), end: CGPoint(x: 0, y: rect.minY), options: [])
        ctx.restoreGState()
    }

    static func softCircle(_ ctx: CGContext, _ center: CGPoint, _ r: CGFloat, _ hex: UInt32, _ a: CGFloat) {
        ctx.saveGState()
        let g = gradient([(0, hex, a), (0.6, hex, a * 0.55), (1, hex, 0)])
        ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: r, options: [])
        ctx.restoreGState()
    }

    struct RNG {
        var s: UInt64
        init(_ seed: UInt64) { s = seed &* 6364136223846793005 &+ 1442695040888963407 }
        mutating func next() -> Double {
            s = s &* 6364136223846793005 &+ 1442695040888963407
            return Double((s >> 33) & 0xffffff) / Double(0x1000000)
        }
        mutating func range(_ a: Double, _ b: Double) -> Double { a + (b - a) * next() }
    }

    static func ridge(_ x: Double, base: Double, amp: Double, seed: Double) -> Double {
        base + amp * (0.5 * sin(x * 0.0021 + seed) + 0.3 * sin(x * 0.0057 + seed * 2.3) + 0.2 * sin(x * 0.013 + seed * 1.7))
    }

    // MARK: sky

    static func sky(size: CGSize, look: Look = .valley) -> SKTexture {
        texture(size) { ctx in
            let r = CGRect(origin: .zero, size: size)
            fillVertical(ctx, r, look.sky)
            if let g = look.glow { softCircle(ctx, CGPoint(x: size.width * g.x, y: size.height * g.y), g.r, g.hex, g.a) }
            if look.stars {
                var rng = RNG(7)
                for _ in 0..<110 {
                    let x = rng.range(0, Double(size.width)), y = rng.range(Double(size.height) * 0.25, Double(size.height))
                    ctx.setFillColor(c(0xf4f1e6, CGFloat(rng.range(0.25, 0.9))))
                    let d = CGFloat(rng.range(0.8, 2.0))
                    ctx.fillEllipse(in: CGRect(x: x, y: y, width: Double(d), height: Double(d)))
                }
            }
        }
    }

    static func cloud(width: CGFloat, seed: UInt64, tone: UInt32 = 0xeef0f0, alpha: CGFloat = 0.55) -> SKTexture {
        let size = CGSize(width: width, height: width * 0.32)
        return texture(size) { ctx in
            var rng = RNG(seed)
            for _ in 0..<22 {
                let x = rng.range(0.16, 0.84) * Double(size.width)
                let y = rng.range(0.42, 0.58) * Double(size.height)
                let r = rng.range(0.07, 0.12) * Double(size.width)
                softCircle(ctx, CGPoint(x: x, y: y), CGFloat(r), tone, alpha)
            }
        }
    }

    // MARK: parallax layers (drawn in chunks so no texture gets huge)

    /// Far mountains: two hazy ridges. Chunk covers layer-x in [x0, x0+w).
    static func mountainChunk(x0: CGFloat, w: CGFloat, h: CGFloat, look: Look = .valley) -> SKTexture {
        texture(CGSize(width: w, height: h)) { ctx in
            for (i, layer) in [(0.62, look.far[0], 0.9), (0.42, look.far[1], 1.0)].enumerated() {
                let top = h * CGFloat(layer.0)
                let path = CGMutablePath()
                path.move(to: CGPoint(x: 0, y: 0))
                var x: CGFloat = 0
                while x <= w + 8 {
                    let y = ridge(Double(x + x0), base: Double(top), amp: Double(h) * 0.16, seed: Double(i) * 3.1 + 0.4)
                    path.addLine(to: CGPoint(x: x, y: CGFloat(y)))
                    x += 8
                }
                path.addLine(to: CGPoint(x: w + 8, y: 0))
                path.closeSubpath()
                ctx.saveGState()
                ctx.addPath(path)
                ctx.clip()
                fillVertical(ctx, CGRect(x: 0, y: 0, width: w, height: h),
                             [(0, layer.1, 1), (0.55, layer.1, 1), (1, look.mist, CGFloat(layer.2) * 0.9)])
                ctx.restoreGState()
            }
            // Mist at the foot.
            fillVertical(ctx, CGRect(x: 0, y: 0, width: w, height: h * 0.35), [(0, 0xdcd8cd, 0.0), (1, 0xdcd8cd, 0.0)])
        }
    }

    /// Mid-distance wooded hills.
    static func hillChunk(x0: CGFloat, w: CGFloat, h: CGFloat, look: Look = .valley) -> SKTexture {
        texture(CGSize(width: w, height: h)) { ctx in
            let top = h * 0.55
            let path = CGMutablePath()
            path.move(to: .zero)
            var x: CGFloat = 0
            while x <= w + 8 {
                path.addLine(to: CGPoint(x: x, y: CGFloat(ridge(Double(x + x0), base: Double(top), amp: Double(h) * 0.17, seed: 5.2))))
                x += 8
            }
            path.addLine(to: CGPoint(x: w + 8, y: 0))
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            fillVertical(ctx, CGRect(x: 0, y: 0, width: w, height: h), look.hill)
            ctx.restoreGState()
            // Conifers along the ridge, positions derived from absolute x so chunks line up.
            let step: CGFloat = 26
            var gx = (x0 / step).rounded(.down) * step
            while gx < x0 + w + step {
                var rng = RNG(UInt64(abs(gx / step)) &+ 77)
                let ry = CGFloat(ridge(Double(gx), base: Double(top), amp: Double(h) * 0.17, seed: 5.2))
                let th = CGFloat(rng.range(34, 70))
                let tx = gx - x0 + CGFloat(rng.range(-6, 6))
                let ty = ry - CGFloat(rng.range(4, 24))
                if look.hillTrees, rng.next() > 0.18 {
                    ctx.setFillColor(c(rng.next() > 0.5 ? 0x4a6354 : 0x43594b))
                    for k in 0..<3 {
                        let kk = CGFloat(k)
                        let wk = th * (0.32 - kk * 0.07)
                        let yb = ty + th * kk * 0.28
                        ctx.move(to: CGPoint(x: tx - wk, y: yb))
                        ctx.addLine(to: CGPoint(x: tx, y: yb + th * 0.5))
                        ctx.addLine(to: CGPoint(x: tx + wk, y: yb))
                        ctx.closePath()
                    }
                    ctx.fillPath()
                }
                gx += step
            }
        }
    }

    // MARK: terrain

    /// Terrain chunk covering world x in [x0, x0+w), world y in [yMin, yMax].
    static func terrainChunk(mission: Mission, x0: CGFloat, w: CGFloat, yMin: CGFloat, yMax: CGFloat) -> SKTexture {
        let h = yMax - yMin
        let look = Look.of(mission)
        return texture(CGSize(width: w, height: h)) { ctx in
            func pt(_ x: CGFloat) -> CGPoint { CGPoint(x: x, y: CGFloat(mission.groundHeight(at: Double(x + x0))) - yMin) }
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -2, y: 0))
            var x: CGFloat = -2
            while x <= w + 6 { path.addLine(to: pt(x)); x += 6 }
            path.addLine(to: CGPoint(x: w + 6, y: 0))
            path.closeSubpath()
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            fillVertical(ctx, CGRect(x: 0, y: 0, width: w, height: h),
                         look.ground)
            // Strata lines for texture.
            ctx.setStrokeColor(c(0x2e241d, 0.18))
            ctx.setLineWidth(1)
            var k: CGFloat = 40
            while k < h {
                ctx.beginPath()
                var xx: CGFloat = -2
                while xx <= w + 6 {
                    let p = pt(xx)
                    let y = p.y - k - 8 * CGFloat(sin(Double(xx + x0) * 0.03 + Double(k)))
                    if xx == -2 { ctx.move(to: CGPoint(x: xx, y: y)) } else { ctx.addLine(to: CGPoint(x: xx, y: y)) }
                    xx += 12
                }
                ctx.strokePath()
                k += 46
            }
            ctx.restoreGState()
            // Grass edge.
            let edge = CGMutablePath()
            x = -2
            edge.move(to: pt(x))
            while x <= w + 6 { edge.addLine(to: pt(x)); x += 6 }
            if look.town { drawTownFacades(ctx, mission: mission, x0: x0, w: w, yMin: yMin) }
            ctx.addPath(edge); ctx.setStrokeColor(c(look.edgeDark)); ctx.setLineWidth(look.edgeWide); ctx.setLineJoin(.round); ctx.strokePath()
            ctx.addPath(edge); ctx.setStrokeColor(c(look.edgeLight)); ctx.setLineWidth(look.edgeWide * 0.45); ctx.strokePath()
            guard look.trees else { return }

            // Trees on dry-ish ground, away from buildings and the camp.
            var gx = (x0 / 38).rounded(.down) * 38
            while gx < x0 + w + 38 {
                var rng = RNG(UInt64(abs(gx / 38)) &+ 901)
                let wx = Double(gx) + rng.range(-10, 10)
                let near = mission.rescuePoints.contains { abs($0.x - wx) < $0.width / 2 + 60 }
                let inCamp = abs(wx - mission.base.x) < mission.base.width / 2 + 40
                let dry = mission.waterLevel(from: wx, to: wx, flood: -1000) <= mission.groundHeight(at: wx)
                if dry && !near && !inCamp && rng.next() > 0.45 && wx > 40 && wx < mission.world.width - 40 {
                    let gy = CGFloat(mission.groundHeight(at: wx)) - yMin
                    let size = CGFloat(rng.range(34, 66))
                    drawTree(ctx, x: CGFloat(wx) - x0, y: gy - 3, size: size, conifer: rng.next() > 0.55, rng: &rng)
                }
                gx += 38
            }
        }
    }

    static func drawTree(_ ctx: CGContext, x: CGFloat, y: CGFloat, size: CGFloat, conifer: Bool, rng: inout RNG) {
        ctx.setFillColor(c(0x5a4331))
        ctx.fill(CGRect(x: x - size * 0.04, y: y, width: size * 0.08, height: size * 0.3))
        if conifer {
            for k in 0..<4 {
                let kk = CGFloat(k)
                let w = size * (0.34 - kk * 0.06)
                let yb = y + size * 0.12 + kk * size * 0.2
                ctx.setFillColor(c(k % 2 == 0 ? 0x36553f : 0x3f6148))
                ctx.move(to: CGPoint(x: x - w, y: yb)); ctx.addLine(to: CGPoint(x: x, y: yb + size * 0.34)); ctx.addLine(to: CGPoint(x: x + w, y: yb))
                ctx.closePath(); ctx.fillPath()
            }
        } else {
            for (dx, dy, r, hex) in [(-0.16, 0.5, 0.26, 0x4a7040), (0.16, 0.52, 0.25, 0x56804a), (0.0, 0.7, 0.28, 0x5f8a50)] as [(CGFloat, CGFloat, CGFloat, UInt32)] {
                ctx.setFillColor(c(hex))
                ctx.fillEllipse(in: CGRect(x: x + dx * size - r * size, y: y + dy * size - r * size, width: r * 2 * size, height: r * 2 * size))
            }
        }
    }

    // MARK: buildings

    /// A building from the ground (well below `top`) up to its flat roof at the top edge of the image.
    static func building(kind: String, width: CGFloat, top: CGFloat, seed: UInt64) -> SKTexture {
        let below: CGFloat = 60
        let h = top + below
        let pad: CGFloat = 14
        let size = CGSize(width: width + pad * 2, height: h)
        return texture(size) { ctx in
            var rng = RNG(seed)
            let wallPalette: [UInt32] = [0xe3d6bd, 0xd4b896, 0xc9a58a, 0xdcd7cc]
            let wall = wallPalette[Int(rng.next() * 4) % 4]
            let bx = pad, bw = width
            if kind == "tower" {
                // Concrete shaft with a fat tank under the landing platform.
                let colW = width * 0.34
                let cx = size.width / 2
                fillVertical(ctx, CGRect(x: cx - colW / 2, y: 0, width: colW, height: h - 40), [(0, 0xb9b6ae, 1), (1, 0x9b988f, 1)])
                ctx.setStrokeColor(c(0x7e7b73, 0.7)); ctx.setLineWidth(2)
                var yy: CGFloat = 20
                while yy < h - 50 { ctx.move(to: CGPoint(x: cx - colW / 2, y: yy)); ctx.addLine(to: CGPoint(x: cx + colW / 2, y: yy)); ctx.strokePath(); yy += 34 }
                ctx.saveGState()
                ctx.addEllipse(in: CGRect(x: bx + 4, y: h - 78, width: bw - 8, height: 62)); ctx.clip()
                fillVertical(ctx, CGRect(x: bx, y: h - 80, width: bw, height: 66), [(0, 0xd9d6cc, 1), (1, 0xa7a49a, 1)])
                ctx.restoreGState()
                ctx.setFillColor(c(0x6b6861)); ctx.fill(CGRect(x: bx - 6, y: h - 18, width: bw + 12, height: 18))
                ctx.setFillColor(c(0x8c8a83)); ctx.fill(CGRect(x: bx - 6, y: h - 5, width: bw + 12, height: 5))
                return
            }
            // Walls
            fillVertical(ctx, CGRect(x: bx, y: 0, width: bw, height: h - 12), [(0, wall, 1), (1, wall, 1)])
            ctx.setFillColor(c(0x000000, 0.10)); ctx.fill(CGRect(x: bx + bw * 0.78, y: 0, width: bw * 0.22, height: h - 12))
            // Windows in rows
            let rows = max(1, Int((h - 12 - 70) / 46))
            let cols = max(2, Int(bw / 44))
            for r in 0..<rows {
                for k in 0..<cols {
                    let wx = bx + (CGFloat(k) + 0.5) * bw / CGFloat(cols) - 9
                    let wy = h - 12 - 40 - CGFloat(r) * 46
                    if wy < 24 { continue }
                    fillVertical(ctx, CGRect(x: wx, y: wy, width: 18, height: 26), [(0, 0x7d95a3, 1), (1, 0x4d6573, 1)])
                    ctx.setStrokeColor(c(0xfffdf9, 0.8)); ctx.setLineWidth(1.5)
                    ctx.stroke(CGRect(x: wx, y: wy, width: 18, height: 26))
                }
            }
            // Door near the bottom
            ctx.setFillColor(c(0x6a4c3a)); ctx.fill(CGRect(x: bx + bw * 0.5 - 8, y: 4, width: 16, height: 30))
            // Roof slab with railing
            ctx.setFillColor(c(0x5d5a55)); ctx.fill(CGRect(x: bx - 8, y: h - 12, width: bw + 16, height: 12))
            ctx.setFillColor(c(0x8a867f)); ctx.fill(CGRect(x: bx - 8, y: h - 4, width: bw + 16, height: 4))
            // Landing marking: dashed line on the roof
            ctx.setFillColor(c(0xe9c85a, 0.9))
            var dx = bx + 10
            while dx < bx + bw - 14 { ctx.fill(CGRect(x: dx, y: h - 3.5, width: 14, height: 2)); dx += 24 }
            // Terracotta stripe
            ctx.setFillColor(c(0xc75d3b, 0.85)); ctx.fill(CGRect(x: bx, y: h - 24, width: bw, height: 5))
        }
    }

    /// Rescue camp: pad, tent, fuel tank, lamp mast. Anchored at bottom centre on the pad surface.
    static func camp(width: CGFloat) -> SKTexture {
        let size = CGSize(width: width + 60, height: 150)
        return texture(size) { ctx in
            let x0: CGFloat = 30
            // Pad slab
            fillVertical(ctx, CGRect(x: x0, y: 0, width: width, height: 8), [(0, 0x77746e, 1), (1, 0x57544f, 1)])
            ctx.setFillColor(c(0xe9c85a)); ctx.fill(CGRect(x: x0 + width * 0.30, y: 5, width: width * 0.40, height: 2))
            // Edge lights
            for i in 0...8 {
                let lx = x0 + 6 + CGFloat(i) * (width - 12) / 8
                softCircle(ctx, CGPoint(x: lx, y: 10), 7, 0xff9b4a, 0.9)
                ctx.setFillColor(c(0xffd9a0)); ctx.fillEllipse(in: CGRect(x: lx - 1.5, y: 8.5, width: 3, height: 3))
            }
            // Tent (left)
            let tx = x0 + 8
            ctx.setFillColor(c(0xf1ece2))
            ctx.move(to: CGPoint(x: tx, y: 8)); ctx.addLine(to: CGPoint(x: tx + 10, y: 52)); ctx.addLine(to: CGPoint(x: tx + 62, y: 70))
            ctx.addLine(to: CGPoint(x: tx + 118, y: 52)); ctx.addLine(to: CGPoint(x: tx + 126, y: 8)); ctx.closePath(); ctx.fillPath()
            ctx.setFillColor(c(0xc75d3b))
            ctx.move(to: CGPoint(x: tx + 10, y: 52)); ctx.addLine(to: CGPoint(x: tx + 62, y: 70)); ctx.addLine(to: CGPoint(x: tx + 118, y: 52))
            ctx.addLine(to: CGPoint(x: tx + 117, y: 44)); ctx.addLine(to: CGPoint(x: tx + 62, y: 62)); ctx.addLine(to: CGPoint(x: tx + 11, y: 44)); ctx.closePath(); ctx.fillPath()
            ctx.setFillColor(c(0x4a4340)); ctx.move(to: CGPoint(x: tx + 52, y: 8)); ctx.addLine(to: CGPoint(x: tx + 58, y: 38))
            ctx.addLine(to: CGPoint(x: tx + 74, y: 38)); ctx.addLine(to: CGPoint(x: tx + 80, y: 8)); ctx.closePath(); ctx.fillPath()
            // Fuel tank (right)
            let fx = x0 + width - 70
            fillVertical(ctx, CGRect(x: fx, y: 8, width: 46, height: 40), [(0, 0xe8e4dc, 1), (1, 0xb4b0a6, 1)])
            ctx.setFillColor(c(0xc75d3b)); ctx.fill(CGRect(x: fx, y: 24, width: 46, height: 7))
            ctx.setFillColor(c(0x57544f)); ctx.fill(CGRect(x: fx + 18, y: 48, width: 10, height: 6))
            // Lamp mast
            ctx.setFillColor(c(0x57544f)); ctx.fill(CGRect(x: x0 + width - 14, y: 8, width: 4, height: 110))
            softCircle(ctx, CGPoint(x: x0 + width - 12, y: 118), 16, 0xffe6b0, 0.7)
            // Windsock pole
            ctx.fill(CGRect(x: x0 + width * 0.5 - 2, y: 8, width: 4, height: 96))
        }
    }

    static func sock() -> SKTexture {
        texture(CGSize(width: 40, height: 14)) { ctx in
            for i in 0..<5 {
                ctx.setFillColor(c(i % 2 == 0 ? 0xc75d3b : 0xf1ece2))
                let x = CGFloat(i) * 8
                ctx.move(to: CGPoint(x: x, y: 1 + CGFloat(i) * 0.5)); ctx.addLine(to: CGPoint(x: x + 8, y: 2 + CGFloat(i) * 0.7))
                ctx.addLine(to: CGPoint(x: x + 8, y: 12 - CGFloat(i) * 0.7)); ctx.addLine(to: CGPoint(x: x, y: 13 - CGFloat(i) * 0.5)); ctx.closePath(); ctx.fillPath()
            }
        }
    }

    private static let cached_marker: SKTexture = make_marker()
    static func marker() -> SKTexture { cached_marker }
    private static func make_marker() -> SKTexture {
        texture(CGSize(width: 34, height: 40)) { ctx in
            ctx.setFillColor(c(0xc75d3b))
            ctx.move(to: CGPoint(x: 17, y: 2)); ctx.addLine(to: CGPoint(x: 31, y: 24)); ctx.addLine(to: CGPoint(x: 22, y: 24))
            ctx.addLine(to: CGPoint(x: 22, y: 38)); ctx.addLine(to: CGPoint(x: 12, y: 38)); ctx.addLine(to: CGPoint(x: 12, y: 24)); ctx.addLine(to: CGPoint(x: 3, y: 24))
            ctx.closePath(); ctx.fillPath()
            ctx.setStrokeColor(c(0xfffdf9, 0.9)); ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: 17, y: 2)); ctx.addLine(to: CGPoint(x: 31, y: 24)); ctx.addLine(to: CGPoint(x: 22, y: 24)); ctx.addLine(to: CGPoint(x: 22, y: 38))
            ctx.addLine(to: CGPoint(x: 12, y: 38)); ctx.addLine(to: CGPoint(x: 12, y: 24)); ctx.addLine(to: CGPoint(x: 3, y: 24)); ctx.closePath(); ctx.strokePath()
        }
    }

    // MARK: helicopter

    /// Side view, facing right. 132 x 60 points; the skids touch the bottom edge. Rotor is a separate node.
    static func helicopterSide() -> SKTexture {
        texture(CGSize(width: 132, height: 60)) { ctx in
            // Tail boom
            ctx.setFillColor(c(0xb94f30))
            ctx.move(to: CGPoint(x: 38, y: 34)); ctx.addLine(to: CGPoint(x: 6, y: 38)); ctx.addLine(to: CGPoint(x: 6, y: 42)); ctx.addLine(to: CGPoint(x: 40, y: 46)); ctx.closePath(); ctx.fillPath()
            // Tail fin
            ctx.setFillColor(c(0xa7472c))
            ctx.move(to: CGPoint(x: 6, y: 38)); ctx.addLine(to: CGPoint(x: 2, y: 56)); ctx.addLine(to: CGPoint(x: 12, y: 56)); ctx.addLine(to: CGPoint(x: 16, y: 40)); ctx.closePath(); ctx.fillPath()
            // Body
            ctx.saveGState()
            let body = CGPath(roundedRect: CGRect(x: 30, y: 14, width: 78, height: 34), cornerWidth: 16, cornerHeight: 16, transform: nil)
            ctx.addPath(body); ctx.clip()
            fillVertical(ctx, CGRect(x: 30, y: 14, width: 78, height: 34), [(0, 0xe0714c, 1), (0.55, 0xc75d3b, 1), (1, 0x8f3a22, 1)])
            ctx.setFillColor(c(0xfffdf9)); ctx.fill(CGRect(x: 30, y: 27, width: 78, height: 6))
            ctx.restoreGState()
            // Engine hump
            ctx.setFillColor(c(0xa7472c)); ctx.fill(CGRect(x: 52, y: 46, width: 30, height: 6))
            // Cockpit glass
            ctx.saveGState()
            let glass = CGPath(ellipseIn: CGRect(x: 78, y: 24, width: 32, height: 22), transform: nil)
            ctx.addPath(glass); ctx.clip()
            fillVertical(ctx, CGRect(x: 78, y: 24, width: 32, height: 22), [(0, 0xcfe6ee, 1), (1, 0x5d8296, 1)])
            ctx.restoreGState()
            ctx.setFillColor(c(0xffffff, 0.55)); ctx.fillEllipse(in: CGRect(x: 86, y: 38, width: 12, height: 4))
            // Side door line
            ctx.setStrokeColor(c(0x6b2b19, 0.7)); ctx.setLineWidth(1)
            ctx.stroke(CGRect(x: 48, y: 18, width: 22, height: 22))
            // Skids
            ctx.setStrokeColor(c(0x2e2b29)); ctx.setLineWidth(3); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 38, y: 3)); ctx.addLine(to: CGPoint(x: 106, y: 3)); ctx.addLine(to: CGPoint(x: 112, y: 8)); ctx.strokePath()
            ctx.setLineWidth(2.4)
            ctx.move(to: CGPoint(x: 52, y: 4)); ctx.addLine(to: CGPoint(x: 56, y: 16)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 88, y: 4)); ctx.addLine(to: CGPoint(x: 84, y: 16)); ctx.strokePath()
            // Mast
            ctx.setFillColor(c(0x3a3735)); ctx.fill(CGRect(x: 64, y: 50, width: 5, height: 7))
        }
    }

    static func helicopterFront() -> SKTexture {
        texture(CGSize(width: 74, height: 60)) { ctx in
            ctx.saveGState()
            let body = CGPath(roundedRect: CGRect(x: 18, y: 14, width: 38, height: 36), cornerWidth: 17, cornerHeight: 17, transform: nil)
            ctx.addPath(body); ctx.clip()
            fillVertical(ctx, CGRect(x: 18, y: 14, width: 38, height: 36), [(0, 0xe0714c, 1), (0.6, 0xc75d3b, 1), (1, 0x8f3a22, 1)])
            ctx.restoreGState()
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: 23, y: 22, width: 28, height: 22)); ctx.clip()
            fillVertical(ctx, CGRect(x: 23, y: 22, width: 28, height: 22), [(0, 0xcfe6ee, 1), (1, 0x5d8296, 1)])
            ctx.restoreGState()
            ctx.setFillColor(c(0xfffdf9)); ctx.fill(CGRect(x: 18, y: 15, width: 38, height: 4))
            ctx.setStrokeColor(c(0x2e2b29)); ctx.setLineWidth(3); ctx.setLineCap(.round)
            ctx.move(to: CGPoint(x: 8, y: 3)); ctx.addLine(to: CGPoint(x: 66, y: 3)); ctx.strokePath()
            ctx.setLineWidth(2.4)
            ctx.move(to: CGPoint(x: 22, y: 4)); ctx.addLine(to: CGPoint(x: 26, y: 16)); ctx.strokePath()
            ctx.move(to: CGPoint(x: 52, y: 4)); ctx.addLine(to: CGPoint(x: 48, y: 16)); ctx.strokePath()
            ctx.setFillColor(c(0x3a3735)); ctx.fill(CGRect(x: 35, y: 50, width: 5, height: 7))
        }
    }

    static func rotorBlade() -> SKTexture {
        texture(CGSize(width: 150, height: 6)) { ctx in
            fillVertical(ctx, CGRect(x: 0, y: 0, width: 150, height: 6), [(0, 0x6b6762, 1), (1, 0x2e2b29, 1)])
            ctx.setBlendMode(.destinationIn)
            let g = gradient([(0, 0x000000, 0.0), (0.12, 0x000000, 1), (0.88, 0x000000, 1), (1, 0x000000, 0.0)])
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 150, y: 0), options: [])
        }
    }

    static func rotorDisc() -> SKTexture {
        texture(CGSize(width: 150, height: 14)) { ctx in
            let g = gradient([(0, 0xffffff, 0.0), (0.5, 0xdfe6ea, 0.34), (1, 0xffffff, 0.0)])
            ctx.saveGState()
            ctx.addEllipse(in: CGRect(x: 0, y: 1, width: 150, height: 12)); ctx.clip()
            ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: 150, y: 0), options: [])
            ctx.restoreGState()
        }
    }

    // MARK: people

    static let vestColors: [UInt32] = [0xf0a030, 0x4f87b0, 0xc75d3b, 0x6aa05a, 0xd8c24a]

    static func person(variant: Int) -> SKTexture {
        texture(CGSize(width: 18, height: 30)) { ctx in
            let vest = vestColors[variant % vestColors.count]
            ctx.setFillColor(c(0x3d4a5a)); ctx.fill(CGRect(x: 5, y: 0, width: 3.5, height: 11)); ctx.fill(CGRect(x: 9.5, y: 0, width: 3.5, height: 11))
            let torso = CGPath(roundedRect: CGRect(x: 4, y: 10, width: 10, height: 11), cornerWidth: 3, cornerHeight: 3, transform: nil)
            ctx.addPath(torso); ctx.setFillColor(c(vest)); ctx.fillPath()
            ctx.setFillColor(c(0xe2b894)); ctx.fillEllipse(in: CGRect(x: 5, y: 21, width: 8, height: 8))
            ctx.setFillColor(c([0x3b2a20, 0x8a5a2f, 0x1f1a17, 0xb8873f][variant % 4])); 
            ctx.fill(CGRect(x: 5, y: 26, width: 8, height: 3))
        }
    }

    private static let cached_arm: SKTexture = make_arm()
    static func arm() -> SKTexture { cached_arm }
    private static func make_arm() -> SKTexture {
        texture(CGSize(width: 4, height: 12)) { ctx in
            ctx.setFillColor(c(0xe2b894)); ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 12))
            ctx.setFillColor(c(0x3d4a5a, 0.0)); ctx.fill(.zero)
        }
    }

    // MARK: effects

    private static let cached_puff: SKTexture = make_puff()
    static func puff() -> SKTexture { cached_puff }
    private static func make_puff() -> SKTexture {
        texture(CGSize(width: 32, height: 32)) { ctx in softCircle(ctx, CGPoint(x: 16, y: 16), 16, 0xffffff, 0.9) }
    }

    private static let cached_raindrop: SKTexture = make_raindrop()
    static func raindrop() -> SKTexture { cached_raindrop }
    private static func make_raindrop() -> SKTexture {
        texture(CGSize(width: 3, height: 22)) { ctx in
            fillVertical(ctx, CGRect(x: 0, y: 0, width: 3, height: 22), [(0, 0xdfe9ee, 0.0), (1, 0xdfe9ee, 0.8)])
        }
    }

    static func waterBody(height: CGFloat) -> SKTexture {
        texture(CGSize(width: 8, height: height)) { ctx in
            fillVertical(ctx, CGRect(x: 0, y: 0, width: 8, height: height),
                         [(0, 0x5f8d99, 0.72), (0.2, 0x4b7685, 0.78), (1, 0x2a4552, 0.9)])
        }
    }
}

// MARK: - Fire and water (0.2)

extension Art {
    /// A flame tongue: bright core, orange body, soft edge. Tinted per particle.
    private static let cached_flame: SKTexture = make_flame()
    static func flame() -> SKTexture { cached_flame }
    private static func make_flame() -> SKTexture {
        texture(CGSize(width: 40, height: 56)) { ctx in
            softCircle(ctx, CGPoint(x: 20, y: 18), 20, 0xe8480f, 0.95)
            softCircle(ctx, CGPoint(x: 20, y: 26), 13, 0xff8a1f, 0.9)
            softCircle(ctx, CGPoint(x: 20, y: 30), 6, 0xffcf5a, 0.8)
        }
    }

    /// Ash and charred ground under a burnt stretch.
    private static var scorchCache: [CGFloat: SKTexture] = [:]
    static func scorch(width: CGFloat) -> SKTexture {
        if let t = scorchCache[width] { return t }
        let t = makeScorch(width: width)
        scorchCache[width] = t
        return t
    }
    private static func makeScorch(width: CGFloat) -> SKTexture {
        texture(CGSize(width: width, height: 26)) { ctx in
            ctx.saveGState()
            ctx.translateBy(x: width / 2, y: 6)
            ctx.scaleBy(x: width / 26, y: 1)
            softCircle(ctx, .zero, 13, 0x15110f, 0.8)
            ctx.restoreGState()
        }
    }

    /// A droplet of extinguishing water.
    private static let cached_waterDrop: SKTexture = make_waterDrop()
    static func waterDrop() -> SKTexture { cached_waterDrop }
    private static func make_waterDrop() -> SKTexture {
        texture(CGSize(width: 8, height: 12)) { ctx in
            ctx.setFillColor(c(0xcfe6f2, 0.95))
            ctx.fillEllipse(in: CGRect(x: 1, y: 0.5, width: 6, height: 8))
            ctx.setFillColor(c(0xeaf5fb, 0.95))
            ctx.fillEllipse(in: CGRect(x: 2.4, y: 6, width: 3.2, height: 5))
        }
    }
}
