import SwiftUI
import RotorwachtCore

/// One list of the best endless runs: place, name, stages, points, date.
struct EndlessScoreListView: View {
    let entries: [EndlessEntry]
    var highlight: (place: Int, date: Date)? = nil
    var compact = false

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "dd.MM.yy"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("Noch keine Läufe.").font(Theme.text(13)).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                let mine = highlight?.place == i && highlight?.date == e.date
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(Theme.mono(12)).foregroundColor(mine ? Theme.accentStrong : Theme.muted).frame(width: 22, alignment: .trailing)
                    Text(e.name).font(mine ? Theme.textMedium(compact ? 13 : 14) : Theme.text(compact ? 13 : 14))
                        .foregroundColor(mine ? Theme.accentStrong : Theme.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text("Stufe \(e.stages)").font(Theme.mono(11)).foregroundColor(mine ? Theme.accent : Theme.muted)
                    Text("\(e.score)").font(Theme.mono(13)).foregroundColor(Theme.ink).frame(width: 56, alignment: .trailing)
                    if !compact {
                        Text(Self.dateFormat.string(from: e.date)).font(Theme.mono(11)).foregroundColor(Theme.muted).frame(width: 64, alignment: .trailing)
                    }
                }
                .padding(.vertical, compact ? 4 : 6)
                .padding(.horizontal, 6)
                .background(mine ? Theme.soft : Color.clear)
                .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
            }
        }
    }
}

/// Right side of the result card in the endless mode: where the run stands, and the list once it is over.
struct EndlessSidePanel: View {
    @EnvironmentObject var model: AppModel
    let run: EndlessRun
    let next: EndlessRun.Next?

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k).font(Theme.text(13)).foregroundColor(Theme.muted)
            Spacer()
            Text(v).font(Theme.mono(13)).foregroundColor(Theme.ink)
        }
        .padding(.vertical, 5)
        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(run.isOver ? "Endlos · Lauf beendet" : "Endlos · Lauf läuft")
            VStack(spacing: 0) {
                row("Stufen geschafft", "\(run.stagesCleared)")
                row("Punkte im Lauf", "\(run.score)")
                row("Hubschrauber im Bestand", "\(run.helicopters)")
            }
            if next == .next(bonusHelicopter: true) {
                Text("Ein Ersatzhubschrauber kommt dazu.").font(Theme.mono(11)).foregroundColor(Theme.accentStrong)
            }
            if run.isOver {
                Eyebrow("Bestenliste · Endlos · \(run.level.label)").padding(.top, 8)
                EndlessScoreListView(entries: model.endlessScores.list(run.level), highlight: model.lastEndlessEntry, compact: true)
            } else {
                Text("Weiter mit dem nächsten Einsatz: etwas schwerer, die Hubschrauber bleiben im Bestand.")
                    .font(Theme.text(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Start sheet of the endless mode: rules and the best runs.
struct EndlessSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Endlos · ohne Ende")
            AccentTitle(plain: "Einsatz um ", accent: "Einsatz", size: 34)
            Text("Zufällig zusammengesetzte Einsätze aus den Bausteinen der Kampagnen-Einsätze, einer nach dem anderen, jeder etwas schwerer. Du startest mit \(EndlessRun.startHelicopters(model.difficulty)) Hubschraubern für den ganzen Lauf, nach je \(EndlessRun.bonusEvery) geschafften Stufen kommt einer dazu (höchstens \(EndlessRun.startHelicopters(model.difficulty) + EndlessRun.maxHelicopters - EndlessRun.startHelicopters)). Eine Stufe ist geschafft, wenn mindestens die Hälfte gerettet ist. Der Lauf endet, wenn weniger gerettet wird oder kein Hubschrauber mehr da ist.")
                .font(Theme.text(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Eyebrow("Stufe")
                ForEach(Difficulty.allCases, id: \.self) { l in
                    Button(l.label) { model.difficulty = l }.buttonStyle(LevelButtonStyle(selected: model.difficulty == l))
                }
            }
            Eyebrow("Bestenliste · \(model.difficulty.label) · Stufen, dann Punkte")
            EndlessScoreListView(entries: model.endlessScores.list(model.difficulty))
            HStack {
                Button("Schließen") { model.showEndless = false }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Lauf starten") { model.startEndless() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: 540)
        .background(Theme.bg)
    }
}
