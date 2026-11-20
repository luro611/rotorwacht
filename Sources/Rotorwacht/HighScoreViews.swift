import SwiftUI
import RotorwachtCore

/// One list of the best results: place, name, stars, points, date. `highlight` marks the player's own new entry.
struct ScoreListView: View {
    let entries: [ScoreEntry]
    var highlight: (place: Int, date: Date)? = nil
    var compact = false

    private static let dateFormat: DateFormatter = {
        let f = DateFormatter(); f.locale = Locale(identifier: "de_DE"); f.dateFormat = "dd.MM.yy"; return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            if entries.isEmpty {
                Text("Noch keine Einträge.").font(Theme.text(13)).foregroundColor(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
            }
            ForEach(Array(entries.enumerated()), id: \.offset) { i, e in
                let mine = highlight?.place == i && highlight?.date == e.date
                HStack(spacing: 10) {
                    Text("\(i + 1)").font(Theme.mono(12)).foregroundColor(mine ? Theme.accentStrong : Theme.muted).frame(width: 22, alignment: .trailing)
                    Text(e.name).font(mine ? Theme.textMedium(compact ? 13 : 14) : Theme.text(compact ? 13 : 14))
                        .foregroundColor(mine ? Theme.accentStrong : Theme.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(String(repeating: "★", count: e.stars) + String(repeating: "☆", count: 3 - min(3, e.stars)))
                        .font(.system(size: 11)).foregroundColor(mine ? Theme.accent : Theme.muted)
                    Text("\(e.score)").font(Theme.mono(13)).foregroundColor(Theme.ink).frame(width: 52, alignment: .trailing)
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

/// The Bestenliste of the start menu: choose Einsatz and level.
struct HighScoreSheet: View {
    @EnvironmentObject var model: AppModel
    private var missionID: String { model.scoreMission }
    private var level: Difficulty { model.scoreLevel }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Bestenliste · Top 10")
            AccentTitle(plain: "Die besten ", accent: "Piloten", size: 34)
            HStack(spacing: 8) {
                ForEach(Array(model.missions.enumerated()), id: \.element.id) { _, m in
                    Button("\(m.number ?? 1)") { model.scoreMission = m.id }
                        .buttonStyle(LevelButtonStyle(selected: missionID == m.id))
                        .help(m.title)
                }
                Spacer()
                ForEach(Difficulty.allCases, id: \.self) { l in
                    Button(l.label) { model.scoreLevel = l }.buttonStyle(LevelButtonStyle(selected: level == l))
                }
            }
            if let m = model.missions.first(where: { $0.id == missionID }) {
                Text("Einsatz \(m.number ?? 1) · \(m.title)").font(Theme.mono(12)).foregroundColor(Theme.muted)
            }
            ScoreListView(entries: model.scores(missionID, level))
            HStack {
                Text("Gespeichert auf diesem Mac. Name ändern: Einstellungen (Cmd+,).").font(Theme.mono(10)).foregroundColor(Theme.muted)
                Spacer()
                Button("Schließen") { model.showScores = false }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: 520)
        .background(Theme.bg)
        .onAppear { model.scoreLevel = model.difficulty; model.scoreMission = model.missions.first?.id ?? model.scoreMission }
    }
}

/// Name field on the result card, shown until the name has been confirmed once.
struct NameField: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Text("Name").font(Theme.mono(11)).foregroundColor(Theme.muted)
            TextField("Pilot", text: $model.nameDraft)
                .textFieldStyle(.plain).font(Theme.text(13)).foregroundColor(Theme.ink)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
                .onSubmit { model.confirmName(model.nameDraft) }
            Button("Eintragen") { model.confirmName(model.nameDraft) }.buttonStyle(QuietButtonStyle())
        }
    }
}

/// Practice mode: pick a course, level and optionally slower hazards.
struct PracticeSheet: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow("Üben · ohne Wertung")
            AccentTitle(plain: "Gefahren ", accent: "üben", size: 34)
            Text("Unbegrenzt Hubschrauber, nach einem Verlust geht es sofort am Start weiter. Kein Punktestand, keine Bestenliste, der Fortschritt bleibt unverändert.")
                .font(Theme.text(12)).foregroundColor(Theme.muted).fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Practice.courses, id: \.id) { c in
                    let on = model.practiceCourse == c.id
                    Button { model.practiceCourse = c.id } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(c.title).font(on ? Theme.textMedium(14) : Theme.text(14)).foregroundColor(on ? Theme.accentStrong : Theme.ink)
                            Spacer()
                            Text(c.hint).font(Theme.text(11)).foregroundColor(Theme.muted).lineLimit(1)
                        }
                        .padding(.vertical, 7).padding(.horizontal, 6)
                        .background(on ? Theme.soft : Color.clear)
                        .overlay(Rectangle().fill(Theme.line).frame(height: 1), alignment: .bottom)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack(spacing: 10) {
                Eyebrow("Stufe")
                ForEach(Difficulty.allCases, id: \.self) { l in
                    Button(l.label) { model.difficulty = l }.buttonStyle(LevelButtonStyle(selected: model.difficulty == l))
                }
                Spacer()
                Button(model.practiceSlow ? "Langsamer: an" : "Langsamer: aus") { model.practiceSlow.toggle() }
                    .buttonStyle(LevelButtonStyle(selected: model.practiceSlow))
                    .help("Shutter, Blitze, Salven, Lava und Lawinen langsamer und milder")
            }
            HStack {
                Button("Schließen") { model.showPractice = false }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Üben starten") { model.startPractice() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .padding(.top, 6)
        }
        .padding(26)
        .frame(width: 600)
        .background(Theme.bg)
    }
}
