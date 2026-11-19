import SwiftUI
import RotorwachtCore

@MainActor
final class AppModel: ObservableObject {
    enum Screen: Equatable { case start, playing, result }

    @Published var screen: Screen = .start
    @Published var hud = HUDSnapshot()
    @Published var paused = false
    @Published var result: MissionResult?
    @Published var loadError: String?
    private(set) var scene: GameScene?
    private(set) var mission: Mission?
    /// Which mission is running or was played last (for "Noch einmal").
    private(set) var missionID = MissionLibrary.all[0]
    @Published var missions: [Mission] = []
    /// Stars and scores so far, stored locally.
    @Published private(set) var progress: PlayerProgress
    @Published var difficulty: Difficulty {
        didSet { UserDefaults.standard.set(difficulty.rawValue, forKey: "difficulty") }
    }
    /// Developer aid: `ROTORWACHT_UNLOCK_ALL=1` opens every Einsatz.
    private let unlockAll = ProcessInfo.processInfo.environment["ROTORWACHT_UNLOCK_ALL"] != nil

    static var progressURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Rotorwacht/progress.json")
    }

    init() {
        // Screenshot runs must not touch the player's progress.
        progress = DebugShots.active ? PlayerProgress() : PlayerProgress.load(from: Self.progressURL)
        difficulty = Difficulty(rawValue: UserDefaults.standard.string(forKey: "difficulty") ?? "") ?? .medium
        InputController.shared.start()
        DispatchQueue.main.async { DebugShots.runIfRequested(model: self) }
        InputController.shared.onEscape = { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if !DebugShots.active, self?.screen == .playing { self?.setPaused(true) } }
        }
    }

    func loadMission(_ id: String) -> Mission? {
        do { return try MissionLibrary.load(id) }
        catch let e as MissionLibrary.LoadError { loadError = "Einsatzdatei nicht gefunden: \(e)"; return nil }
        catch { loadError = "Einsatzdatei \(id) ist fehlerhaft: \(error)"; return nil }
    }

    /// Loads the missions for the start menu.
    func loadMissionList() {
        if missions.isEmpty { missions = MissionLibrary.all.compactMap { loadMission($0) } }
    }

    func isUnlocked(_ id: String) -> Bool {
        unlockAll || progress.isUnlocked(id, order: MissionLibrary.all)
    }

    func best(_ id: String) -> MissionRecord? { progress.best(id, difficulty) }

    func startMission(_ id: String? = nil) {
        let id = id ?? missionID
        guard isUnlocked(id), let base = loadMission(id) else { return }
        let m = base.scaled(for: difficulty)
        missionID = id
        mission = m
        let s = GameScene(mission: m)
        s.onHUD = { [weak self] snap in
            DispatchQueue.main.async { self?.hud = snap }
        }
        s.onFinished = { [weak self] r in
            self?.finish(r)
        }
        scene?.shutdown()
        scene = s
        hud = HUDSnapshot()
        paused = false
        result = nil
        InputController.shared.releaseAll()
        InputController.shared.capturing = true
        screen = .playing
    }

    func setPaused(_ p: Bool) {
        guard screen == .playing else { return }
        paused = p
        scene?.gamePaused = p
        scene?.audio.enabled = !p
        if p { InputController.shared.releaseAll() }
    }

    func togglePause() { setPaused(!paused) }

    private func finish(_ r: MissionResult) {
        result = r
        if !DebugShots.active {
            progress.record(missionID: missionID, level: difficulty, result: r)
            progress.save(to: Self.progressURL)
        }
        InputController.shared.capturing = false
        InputController.shared.releaseAll()
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
        screen = .start
    }
}
