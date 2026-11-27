import SwiftUI
import Combine
import RotorwachtCore

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case start, playing, result }

    @Published var screen: Screen = .start
    @Published var hud = HUDSnapshot()
    @Published var paused = false
    @Published var result: MissionResult?
    @Published var loadError: String?
    /// Name of the connected controller (nil = none); drives the hints in the menu and settings.
    @Published private(set) var controllerName: String?
    /// Einsatz cards per row in the start menu.
    static let columns = 5
    /// Controller focus: start menu grid (row 0 = Stufen, then the Einsätze), pause and result buttons.
    @Published var startFocus = GridFocus(rowLengths: [5, 5, 5], row: 1)
    @Published var overlayFocus = 0
    /// Shown in the pause card when the controller was unplugged during the flight.
    @Published var controllerLost = false
    private var resultShownAt = Date.distantFuture
    private var cancellables = Set<AnyCancellable>()
    private(set) var scene: GameScene?
    private(set) var mission: Mission?
    /// Level the running or last Einsatz was started on (the menu setting may change meanwhile).
    private(set) var playedLevel: Difficulty = .medium
    /// Which mission is running or was played last (for "Noch einmal").
    private(set) var missionID = MissionLibrary.all[0]
    @Published var missions: [Mission] = []
    /// Stars and scores so far, stored locally.
    @Published private(set) var progress: PlayerProgress
    /// Best results per Einsatz and level, stored locally.
    @Published private(set) var highScores: HighScores
    /// Name for new entries; asked once on the result card, changeable in the settings.
    @Published var playerName: String {
        didSet { UserDefaults.standard.set(HighScores.cleanName(playerName), forKey: "playerName") }
    }
    /// Bestenliste sheet of the start menu and the name field of the result card.
    @Published var showScores = false
    @Published var scoreMission = MissionLibrary.all[0]
    @Published var scoreLevel: Difficulty = .medium
    @Published var nameDraft = ""
    /// Endless mode: the run in progress (or just ended), what its last stage led to, and the best runs.
    @Published private(set) var endless: EndlessRun?
    @Published private(set) var endlessNext: EndlessRun.Next?
    @Published private(set) var endlessScores: EndlessScores
    @Published private(set) var lastEndlessEntry: (place: Int, date: Date)?
    @Published var showEndless = false
    private(set) var endlessActive = false
    @Published var nameConfirmed: Bool {
        didSet { UserDefaults.standard.set(nameConfirmed, forKey: "playerNameConfirmed") }
    }
    /// Place and date of the entry made by the last result (nil: did not make the list).
    @Published private(set) var lastEntry: (place: Int, date: Date)?
    /// Music on/off and volumes, stored in the user defaults.
    @Published var sound: SoundSettings {
        didSet {
            if sound != sound.clamped { sound = sound.clamped; return }
            if let data = try? JSONEncoder().encode(sound) { UserDefaults.standard.set(data, forKey: "sound") }
            music.apply(sound)
            scene?.audio.volume = Float(sound.effectsVolume)
        }
    }
    private let music = MusicPlayer()
    private var intensity = IntensityTracker()
    private var lastMusicUpdate: Date?
    /// Music stands still while the game is paused or the window is in the background.
    private var gamePausedForMusic = false
    private var appInactive = false
    @Published var difficulty: Difficulty {
        didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: "difficulty") }
    }
    /// Developer aid: `ROTORWACHT_UNLOCK_ALL=1` opens every Einsatz.
    private let unlockAll = ProcessInfo.processInfo.environment["ROTORWACHT_UNLOCK_ALL"] != nil

    static var progressURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rotorwacht/progress.json")
    }

    static var highScoresURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rotorwacht/highscores.json")
    }

    static var endlessScoresURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rotorwacht/endless.json")
    }

    init() {
        endlessScores = DebugShots.active ? EndlessScores() : EndlessScores.load(from: Self.endlessScoresURL)
        highScores = DebugShots.active ? HighScores() : HighScores.load(from: Self.highScoresURL)
        playerName = UserDefaults.standard.string(forKey: "playerName") ?? HighScores.cleanName(NSUserName())
        nameConfirmed = UserDefaults.standard.bool(forKey: "playerNameConfirmed")
        // Screenshot runs must not touch the player's progress.
        progress = DebugShots.active ? PlayerProgress() : PlayerProgress.load(from: Self.progressURL)
        difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "difficulty") ?? "") ?? .medium
        sound = (UserDefaults.standard.data(forKey: "sound").flatMap { try? JSONDecoder().decode(SoundSettings.self, from: $0) } ?? SoundSettings()).clamped
        InputController.shared.start()
        setupGamepad()
        if !DebugShots.active {
            music.apply(sound)
            music.start()
            music.play(.menu)
        }
        DispatchQueue.main.async { DebugShots.runIfRequested(model: self) }
        InputController.shared.onEscape = { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.appInactive = true; self?.updateMusicPause()
                if !DebugShots.active, self?.screen == .playing { self?.setPaused(true) }
            }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.appInactive = false; self?.updateMusicPause() }
        }
    }

    private func setupGamepad() {
        let pad = GamepadController.shared
        if !DebugShots.active { pad.start() }
        controllerName = pad.name
        pad.$name.receive(on: DispatchQueue.main).sink { [weak self] n in self?.controllerName = n }.store(in: &cancellables)
        pad.onOutput = { [weak self] out in self?.handlePad(out) }
        pad.onDisconnect = { [weak self] in
            guard let self, self.screen == .playing else { return }
            self.controllerLost = true
            self.setPaused(true)
        }
    }

    private func rebuildStartFocus() {
        let n = missions.count
        var rows = [Difficulty.allCases.count]
        var left = n
        while left > 0 { rows.append(min(Self.columns, left)); left -= Self.columns }
        startFocus = GridFocus(rowLengths: rows, row: n > 0 ? 1 : 0)
    }

    private func handlePad(_ out: GamepadOutput) {
        if DebugShots.active { return }
        switch screen {
        case .start:
            for m in out.moves { startFocus.move(m) }
            if out.confirm { activateStartFocus() }
        case .playing:
            if !paused {
                if out.pause { setPaused(true) }
            } else {
                for m in out.moves { if m == .left { overlayFocus = 0 } else if m == .right { overlayFocus = 1 } }
                if out.pause || out.back { setPaused(false) }
                else if out.confirm { if overlayFocus == 0 { setPaused(false) } else { backToStart() } }
            }
        case .result:
            for m in out.moves { if m == .left { overlayFocus = 0 } else if m == .right { overlayFocus = 1 } }
            // The fire button may still be pressed when the card appears; give it a moment.
            guard Date().timeIntervalSince(resultShownAt) > 1.0 else { return }
            if out.back { backToStart() }
            else if out.confirm { if overlayFocus == 0 { playAgain() } else { backToStart() } }
        }
    }

    private func activateStartFocus() {
        let f = startFocus
        if f.row == 0 {
            difficulty = Difficulty.allCases[min(f.col, Difficulty.allCases.count - 1)]
        } else {
            let i = (f.row - 1) * Self.columns + f.col
            if missions.indices.contains(i) { startMission(missions[i].id) }
        }
    }

    func loadMission(_ id: String) -> Mission? {
        do { return try MissionLibrary.load(id) }
        catch let e as MissionLibrary.LoadError { loadError = "Einsatzdatei nicht gefunden: \(e)"; return nil }
        catch { loadError = "Einsatzdatei \(id) ist fehlerhaft: \(error)"; return nil }
    }

    /// Loads the missions for the start menu.
    func loadMissionList() {
        if missions.isEmpty { missions = MissionLibrary.all.compactMap { loadMission($0) }; rebuildStartFocus() }
    }

    func isUnlocked(_ id: String) -> Bool {
        unlockAll || progress.isUnlocked(id, order: MissionLibrary.all)
    }

    func best(_ id: String) -> MissionRecord? { progress.best(id, difficulty) }

    /// Practice course (no score, no list entry, no progress). Chosen in the practice sheet.
    @Published var showPractice = false
    @Published var practiceCourse = Practice.courses[0].id
    @Published var practiceSlow = false
    private(set) var practicing = false

    func startPractice() {
        guard let c = Practice.course(practiceCourse), let base = loadMission(c.missionID) else { return }
        showPractice = false
        launch(base.practiced(course: c, level: difficulty, slow: practiceSlow), id: c.missionID, practice: true)
    }

    func startMission(_ id: String? = nil) {
        let id = id ?? missionID
        guard isUnlocked(id), let base = loadMission(id) else { return }
        endless = nil
        playedLevel = difficulty
        launch(base.scaled(for: difficulty), id: id, practice: false)
    }

    /// Starts a new endless run with a fresh seed.
    func startEndless() {
        showEndless = false
        endless = EndlessRun(seed: UInt64.random(in: 1...UInt64(UInt32.max)), level: difficulty)
        launchEndlessStage()
    }

    private func launchEndlessStage() {
        guard let run = endless else { return }
        do {
            let m = try run.mission()
            endlessNext = nil
            lastEndlessEntry = nil
            launch(m, id: m.id, practice: false, endless: true)
        } catch {
            loadError = "Endlos-Einsatz konnte nicht erzeugt werden: \(error)"
        }
    }

    /// The main button of the result card: repeat the Einsatz, or go on in the endless run (a new run when it is over).
    func playAgain() {
        if let run = endless { if run.isOver { startEndless() } else { launchEndlessStage() } }
        else { startMission(missionID) }
    }

    private func launch(_ m: Mission, id: String, practice: Bool, endless isEndless: Bool = false) {
        endlessActive = isEndless
        practicing = practice
        missionID = id
        mission = m
        let s = GameScene(mission: m)
        s.onHUD = { [weak self] snap in
            DispatchQueue.main.async { self?.hud = snap; self?.feedMusic(snap) }
        }
        s.onFinished = { [weak self] r in
            self?.finish(r)
        }
        scene?.shutdown()
        scene = s
        s.audio.volume = Float(sound.effectsVolume)
        intensity.reset()
        lastMusicUpdate = nil
        gamePausedForMusic = false
        if !DebugShots.active { music.play(MusicTheme.forMission(id)); updateMusicPause() }
        hud = HUDSnapshot()
        paused = false
        controllerLost = false
        overlayFocus = 0
        result = nil
        InputController.shared.releaseAll()
        InputController.shared.capturing = true
        screen = .playing
    }

    func setPaused(_ p: Bool) {
        guard screen == .playing else { return }
        paused = p
        if p { overlayFocus = 0 } else { controllerLost = false }
        scene?.gamePaused = p
        scene?.audio.enabled = !p
        gamePausedForMusic = p
        updateMusicPause()
        if p { InputController.shared.releaseAll() }
    }

    func togglePause() { setPaused(!paused) }

    /// Renames the entry of the last result (name asked on the result card) and remembers the name.
    func confirmName(_ raw: String) {
        let name = HighScores.cleanName(raw)
        playerName = name
        nameConfirmed = true
        if endlessActive, let e = lastEndlessEntry {
            if endlessScores.rename(place: e.place, date: e.date, to: name, level: endless?.level ?? difficulty), !DebugShots.active { endlessScores.save(to: Self.endlessScoresURL) }
            return
        }
        if let e = lastEntry, highScores.rename(place: e.place, date: e.date, mission: missionID, level: playedLevel, to: name) {
            if !DebugShots.active { highScores.save(to: Self.highScoresURL) }
        }
    }

    /// Developer aid for screenshots: fills the list with sample results and marks one as the last entry.
    func debugSeedScores(for id: String) {
        highScores = HighScores()
        let names = ["Anna", "Jonas", "Mira", "Tobi", "Lena", "Kai", "Sven"]
        for (i, n) in names.enumerated() {
            highScores.add(ScoreEntry(name: n, score: 2900 - i * 260, stars: i < 2 ? 3 : (i < 5 ? 2 : 1), date: Date().addingTimeInterval(-Double(i) * 86_400)), mission: missionID, level: difficulty)
            highScores.add(ScoreEntry(name: n, score: 2900 - i * 260, stars: i < 2 ? 3 : (i < 5 ? 2 : 1), date: Date().addingTimeInterval(-Double(i) * 86_400)), mission: id, level: difficulty)
        }
        let mine = ScoreEntry(name: playerName, score: 2570, stars: 2, date: Date())
        highScores.add(mine, mission: id, level: difficulty)
        if let p = highScores.add(mine, mission: missionID, level: difficulty) { lastEntry = (p, mine.date) }
    }

    func scores(_ id: String, _ level: Difficulty) -> [ScoreEntry] { highScores.list(id, level) }

    private func finish(_ r: MissionResult) {
        if practicing {
            // Practice has no result card, no score and no list entry: back to the menu.
            InputController.shared.capturing = false
            InputController.shared.releaseAll()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.backToStart() }
            return
        }
        result = r
        nameDraft = playerName
        if endlessActive, var run = endless {
            // Endless runs have their own list; stage results touch neither the Einsatz lists nor the progress.
            endlessNext = run.finish(r)
            endless = run
            lastEndlessEntry = nil
            if run.isOver {
                let e = EndlessEntry(name: playerName, stages: run.stagesCleared, score: run.score, date: Date())
                if let place = endlessScores.add(e, level: run.level) {
                    lastEndlessEntry = (place, e.date)
                    if !DebugShots.active { endlessScores.save(to: Self.endlessScoresURL) }
                }
            }
            lastEntry = nil
            InputController.shared.capturing = false
            InputController.shared.releaseAll()
            overlayFocus = 0
            resultShownAt = Date().addingTimeInterval(0.6)
            if !DebugShots.active { music.play(MusicTheme.ending(for: r), crossfade: 0.6) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.screen = .result }
            return
        }
        let entry = ScoreEntry(name: playerName, score: r.score, stars: r.stars, date: Date())
        if let place = highScores.add(entry, mission: missionID, level: playedLevel) {
            lastEntry = (place, entry.date)
            if !DebugShots.active { highScores.save(to: Self.highScoresURL) }
        } else {
            lastEntry = nil
        }
        if !DebugShots.active {
            progress.record(missionID: missionID, level: playedLevel, result: r)
            progress.save(to: Self.progressURL)
        }
        InputController.shared.capturing = false
        InputController.shared.releaseAll()
        overlayFocus = 0
        resultShownAt = Date().addingTimeInterval(0.6)
        if !DebugShots.active { music.play(MusicTheme.ending(for: r), crossfade: 0.6) }
        // A short beat so the last rescue can be seen before the result card appears.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.screen = .result
        }
    }

    func backToStart() {
        scene?.shutdown()
        scene = nil
        InputController.shared.capturing = false
        paused = false
        gamePausedForMusic = false
        screen = .start
        if !DebugShots.active { music.play(.menu); updateMusicPause() }
    }

    private func updateMusicPause() { music.setPaused(gamePausedForMusic || appInactive) }

    /// Derives the music intensity from the on-screen display (a few times per second).
    private func feedMusic(_ h: HUDSnapshot) {
        guard screen == .playing, !DebugShots.active, let m = mission, !paused else { lastMusicUpdate = nil; return }
        let now = Date()
        let dt = min(1, now.timeIntervalSince(lastMusicUpdate ?? now.addingTimeInterval(-0.25)))
        lastMusicUpdate = now
        var i = MusicInputs()
        i.timeUsed = 1 - h.timeLeft / max(1, m.timeLimit)
        i.fuel = h.fuel
        i.durability = h.durability
        let rise = m.flood.maxLevel - m.flood.startLevel
        if m.flood.risePerSecond > 0, rise > 0 { i.flood = (h.floodLevel - m.flood.startLevel) / rise }
        i.fire = Double(h.fires.count) / 14
        i.smoke = h.smoke
        i.heat = h.heat
        i.lost = h.lost
        i.helicoptersLeft = h.helicoptersLeft
        i.crashed = h.crashed
        music.setIntensity(intensity.update(i, dt: dt))
    }
}
