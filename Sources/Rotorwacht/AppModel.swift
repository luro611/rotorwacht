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

    init() {
        InputController.shared.start()
        DispatchQueue.main.async { DebugShots.runIfRequested(model: self) }
        InputController.shared.onEscape = { [weak self] in
            Task { @MainActor in self?.togglePause() }
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if self?.screen == .playing { self?.setPaused(true) } }
        }
    }

    func loadMission() -> Mission? {
        do { return try MissionLibrary.load("hochwasser") }
        catch { loadError = "Einsatzdatei nicht gefunden: \(error)"; return nil }
    }

    func startMission() {
        guard let m = loadMission() else { return }
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
