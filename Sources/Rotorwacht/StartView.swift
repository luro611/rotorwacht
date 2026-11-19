import SwiftUI

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

            missionCard.padding(.top, 20)

            HStack(spacing: 28) {
                key("← → ↑ ↓", "Fliegen")
                key("Esc", "Pause")
                key("Leertaste", "Löschwasser (ab 0.2)")
            }
            .padding(.top, 16)

            Spacer(minLength: 8)
            footer
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var missionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow("Einsatz 1 · Einführung")
            AccentTitle(plain: "Hochwasser im ", accent: "Flusstal", size: 32)
            Text("Der Fluss steigt weiter. Niedrige Dächer gehen zuerst unter, Böen drücken dich vom Kurs. Zwölf Plätze, drei Hubschrauber.")
                .font(Theme.text(14)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Einsatz starten") { model.startMission() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                Text("Eingabetaste").font(Theme.mono(11)).foregroundColor(Theme.muted)
            }
            .padding(.top, 6)
        }
        .padding(22)
        .frame(width: 520, alignment: .leading)
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
