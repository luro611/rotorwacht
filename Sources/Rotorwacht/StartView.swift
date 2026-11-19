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

struct StartView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 8)
            VStack(spacing: 12) {
                Siegel(size: 100)
                Eyebrow("Rettungsstaffel · Version \(appVersion)")
                AccentTitle(plain: "Rotor", accent: "wacht", size: 76)
                Text("Fliege nach der Katastrophe ins Unglücksgebiet, hole Menschen von Dächern und Anhöhen und bringe sie sicher ins Lager.")
                    .font(Theme.text(16)).foregroundColor(Theme.muted)
                    .multilineTextAlignment(.center).frame(maxWidth: 520).fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 20) {
                ForEach(model.missions, id: \.id) { m in missionCard(m) }
            }
            .padding(.top, 20)

            HStack(spacing: 28) {
                key("← → ↑ ↓", "Fliegen")
                key("Esc", "Pause")
                key("Leertaste", "Löschwasser")
            }
            .padding(.top, 16)

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
        return VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Einsatz \(m.number ?? 1) · \(m.tagline ?? "")")
            AccentTitle(plain: plain, accent: accent, size: 30)
            Text(m.summary ?? m.briefing)
                .font(Theme.text(14)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            HStack {
                Button("Einsatz starten") { model.startMission(m.id) }
                    .buttonStyle(PrimaryButtonStyle())
                    .modifier(DefaultActionIf(first))
                if first { Text("Eingabetaste").font(Theme.mono(11)).foregroundColor(Theme.muted) }
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 440, height: 250, alignment: .leading)
        .background(Theme.surface)
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
