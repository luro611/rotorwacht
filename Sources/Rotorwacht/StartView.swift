import SwiftUI
import RotorwachtCore

struct Siegel: View {
    @Environment(\.colorScheme) private var scheme
    var size: CGFloat = 150
    var body: some View {
        Group {
            if let img = Res.image(scheme == .dark ? "siegel-dunkel" : "siegel-hell") {
                Image(nsImage: img).resizable().interpolation(.high).scaledToFit()
            } else {
                Color.clear
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel("luro HOMELAB")
    }
}

struct DefaultActionIf: ViewModifier {
    let on: Bool
    init(_ on: Bool) { self.on = on }
    func body(content: Content) -> some View {
        if on { content.keyboardShortcut(.defaultAction) } else { content }
    }
}

struct LevelButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.label(12))
            .foregroundColor(selected ? Theme.accentStrong : Theme.muted)
            .padding(.horizontal, 12).padding(.vertical, 5)
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(selected ? Theme.accent : Theme.line, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

struct StartView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                Siegel(size: 64)
                Eyebrow("Rettungsstaffel · Version \(appVersion)")
                AccentTitle(plain: "Rotor", accent: "wacht", size: 48)
            }

            HStack(spacing: 10) {
                Eyebrow("Stufe")
                ForEach(Difficulty.allCases, id: \.self) { level in
                    Button(level.label) { model.difficulty = level }
                        .buttonStyle(LevelButtonStyle(selected: model.difficulty == level))
                }
            }
            .padding(.top, 16)

            LazyVGrid(columns: Array(repeating: GridItem(.fixed(300), spacing: 16, alignment: .top), count: 3), spacing: 16) {
                ForEach(model.missions, id: \.id) { m in missionCard(m) }
            }
            .padding(.top, 14)

            HStack(spacing: 28) {
                key("← → ↑ ↓", "Fliegen")
                key("Esc", "Pause")
                key("Leertaste", "Löschwasser")
            }
            .padding(.top, 14)

            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { model.loadMissionList() }
    }

    /// Title with the last word as the accent word, as on the website.
    private func split(_ title: String) -> (String, String) {
        guard let i = title.lastIndex(of: " ") else { return ("", title) }
        return (String(title[...i]), String(title[title.index(after: i)...]))
    }

    private func missionCard(_ m: Mission) -> some View {
        let first = m.id == model.missions.first?.id
        let (plain, accent) = split(m.title)
        let open = model.isUnlocked(m.id)
        let best = model.best(m.id)
        return VStack(alignment: .leading, spacing: 8) {
            Eyebrow("Einsatz \(m.number ?? 1) · \(m.tagline ?? "")")
            AccentTitle(plain: plain, accent: accent, size: 24)
            Text(m.summary ?? m.briefing)
                .font(Theme.text(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
                .lineLimit(4)
            Spacer(minLength: 0)
            HStack {
                if open {
                    Button("Einsatz starten") { model.startMission(m.id) }
                        .buttonStyle(PrimaryButtonStyle())
                        .modifier(DefaultActionIf(first))
                    if first { Text("Eingabetaste").font(Theme.mono(10)).foregroundColor(Theme.muted) }
                } else {
                    Text("Gesperrt · schaffe zuerst Einsatz \((m.number ?? 2) - 1)")
                        .font(Theme.mono(10)).foregroundColor(Theme.muted)
                }
                Spacer()
                if let b = best {
                    HStack(spacing: 2) {
                        ForEach(0..<3, id: \.self) { i in
                            Text("★").font(.system(size: 15)).foregroundColor(i < b.stars ? Theme.accent : Theme.line)
                        }
                    }
                }
            }
        }
        .padding(18)
        .frame(width: 300, height: 180, alignment: .leading)
        .background(Theme.surface)
        .opacity(open ? 1 : 0.55)
        .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
    }

    private func key(_ k: String, _ what: String) -> some View {
        HStack(spacing: 8) {
            Text(k).font(Theme.mono(12)).foregroundColor(Theme.ink)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
            Text(what).font(Theme.text(13)).foregroundColor(Theme.muted)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 1)
            HStack {
                Text("Eigenes Spiel, nur für den privaten Gebrauch.").font(Theme.mono(11)).foregroundColor(Theme.muted)
                Spacer()
                Wordmark(size: 22)
            }
        }
        .frame(maxWidth: 900)
        .padding(.bottom, 10)
    }
}
