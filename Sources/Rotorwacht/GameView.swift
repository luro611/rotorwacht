import SwiftUI
import SpriteKit
import RotorwachtCore

struct GameView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            if let scene = model.scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 60, options: [.ignoresSiblingOrder])
                    .ignoresSafeArea()
            }
            HUDView(hud: model.hud)
                .allowsHitTesting(false)
            if model.paused { PauseOverlay() }
            if model.screen == .result, let r = model.result { ResultOverlay(result: r) }
        }
        .background(Color.black)
    }
}

private struct Bar: View {
    let label: String
    let value: Double
    var warnBelow = 0.25
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased()).font(Theme.mono(10)).tracking(1.4).foregroundColor(Theme.muted)
            ZStack(alignment: .leading) {
                Rectangle().fill(Theme.soft)
                GeometryReader { g in
                    Rectangle().fill(value < warnBelow ? Theme.accentStrong : Theme.accent)
                        .frame(width: g.size.width * CGFloat(max(0, min(1, value))))
                }
            }
            .frame(width: 150, height: 6)
            .overlay(Rectangle().stroke(Theme.line, lineWidth: 1))
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var alignment: HorizontalAlignment = .leading
    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(label.uppercased()).font(Theme.mono(10)).tracking(1.4).foregroundColor(Theme.muted)
            Text(value).font(Theme.serif(28)).foregroundColor(Theme.ink)
        }
    }
}

struct HUDView: View {
    let hud: HUDSnapshot

    private func time(_ s: Double) -> String {
        let t = Int(s.rounded(.up))
        return String(format: "%d:%02d", t / 60, t % 60)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 18) {
                panel {
                    VStack(alignment: .leading, spacing: 10) {
                        Bar(label: "Treibstoff", value: hud.fuel)
                        Bar(label: "Haltbarkeit", value: hud.durability)
                    }
                }
                panel {
                    HStack(spacing: 18) {
                        Stat(label: "An Bord", value: "\(hud.aboard)/\(hud.capacity)")
                        Stat(label: "Hubschrauber", value: "\(hud.helicoptersLeft)/\(hud.helicoptersTotal)")
                    }
                }
                Spacer(minLength: 8)
                panel {
                    HStack(spacing: 18) {
                        Stat(label: "Gerettet", value: "\(hud.rescued)/\(hud.total)", alignment: .trailing)
                        Stat(label: "Zeit", value: time(hud.timeLeft), alignment: .trailing)
                    }
                }
            }
            MiniMap(hud: hud).padding(.top, 10)
            Spacer()
            VStack(spacing: 6) {
                ForEach(Array(hud.messages.enumerated()), id: \.offset) { _, m in
                    Text(m).font(Theme.textMedium(14)).foregroundColor(Theme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(Theme.bg.opacity(0.85))
                        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
                }
            }
            .padding(.bottom, 18)
        }
        .padding(16)
    }

    private func panel<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(Theme.bg.opacity(0.82))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
    }
}

/// Thin overview of the whole valley: camp, waiting people, own position.
struct MiniMap: View {
    let hud: HUDSnapshot

    var body: some View {
        Canvas { ctx, size in
            let w = size.width, midY = size.height / 2
            func x(_ v: Double) -> CGFloat { CGFloat(v / hud.worldWidth) * w }
            var line = Path(); line.move(to: CGPoint(x: 0, y: midY)); line.addLine(to: CGPoint(x: w, y: midY))
            ctx.stroke(line, with: .color(Theme.line), lineWidth: 1)
            // Camp
            ctx.fill(Path(CGRect(x: x(hud.baseX) - 6, y: midY - 6, width: 12, height: 12)), with: .color(Theme.ink))
            for p in hud.points where p.waiting > 0 {
                let col = p.endangered ? Theme.accentStrong : Theme.accent
                ctx.fill(Path(ellipseIn: CGRect(x: x(p.x) - 5, y: midY - 5, width: 10, height: 10)), with: .color(col))
                ctx.draw(Text("\(p.waiting)").font(Theme.mono(9)).foregroundColor(Theme.muted), at: CGPoint(x: x(p.x), y: midY - 13))
            }
            var tri = Path()
            let hx = x(hud.heliX)
            tri.move(to: CGPoint(x: hx, y: midY + 3)); tri.addLine(to: CGPoint(x: hx - 5, y: midY + 12)); tri.addLine(to: CGPoint(x: hx + 5, y: midY + 12)); tri.closeSubpath()
            ctx.fill(tri, with: .color(Theme.ink))
        }
        .frame(width: 520, height: 34)
        .padding(.horizontal, 12)
        .background(Theme.bg.opacity(0.82))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
    }
}

struct PauseOverlay: View {
    @EnvironmentObject var model: AppModel
    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(alignment: .leading, spacing: 14) {
                Eyebrow("Pause")
                AccentTitle(plain: "Kurz ", accent: "durchatmen", size: 40)
                HStack(spacing: 10) {
                    Button("Weiter") { model.setPaused(false) }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    Button("Einsatz abbrechen") { model.backToStart() }
                        .buttonStyle(QuietButtonStyle())
                }
                Text("Esc setzt den Einsatz fort.").font(Theme.mono(11)).foregroundColor(Theme.muted)
            }
            .padding(26)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
        }
    }
}

struct ResultOverlay: View {
    @EnvironmentObject var model: AppModel
    let result: MissionResult

    private var headline: (String, String) {
        switch result.outcome {
        case .completed: return ("Einsatz ", "geschafft")
        case .timeUp: return ("Die Zeit ist ", "abgelaufen")
        case .failed: return ("Alle Hubschrauber ", "verloren")
        }
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.text(14)).foregroundColor(Theme.muted)
            Spacer()
            Text(v).font(Theme.mono(14)).foregroundColor(Theme.ink)
        }
        .padding(.vertical, 7)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
            VStack(alignment: .leading, spacing: 12) {
                Eyebrow("Einsatz 1 · Hochwasser im Flusstal")
                AccentTitle(plain: headline.0, accent: headline.1, size: 44)
                HStack(spacing: 4) {
                    ForEach(0..<3, id: \.self) { i in
                        Text("★").font(.system(size: 26)).foregroundColor(i < result.stars ? Theme.accent : Theme.line)
                    }
                    Text("\(result.score) Punkte").font(Theme.mono(13)).foregroundColor(Theme.muted).padding(.leading, 10)
                }
                VStack(spacing: 0) {
                    row("Gerettet", "\(result.rescued) von \(result.total)")
                    row("Vom Wasser erreicht", "\(result.lost)")
                    row("Verletzt oder nicht abgeholt", "\(result.injured)")
                    row("Hubschrauber verloren", "\(result.helicoptersLost)")
                    row("Zeit", String(format: "%d:%02d", Int(result.timeUsed) / 60, Int(result.timeUsed) % 60))
                }
                .padding(.top, 4)
                HStack(spacing: 10) {
                    Button("Noch einmal") { model.startMission() }
                        .buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                    Button("Zum Start") { model.backToStart() }
                        .buttonStyle(QuietButtonStyle())
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(width: 460)
            .background(Theme.surface)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
        }
    }
}
