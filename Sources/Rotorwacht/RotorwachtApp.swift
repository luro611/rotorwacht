import SwiftUI
import SpriteKit
import RotorwachtCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

@main
struct RotorwachtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    init() { Res.registerFonts() }

    var body: some Scene {
        WindowGroup("Rotorwacht") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 540)
        }
        .defaultSize(width: 1280, height: 720)
        Settings {
            SettingsView().environmentObject(model)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            switch model.screen {
            case .start:
                StartView()
            case .playing, .result:
                GameView()
            }
        }
        .alert("Fehler", isPresented: Binding(get: { model.loadError != nil }, set: { if !$0 { model.loadError = nil } })) {
            Button("OK") { model.loadError = nil }
        } message: { Text(model.loadError ?? "") }
    }
}

var appVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
}

struct SettingsView: View {
    @EnvironmentObject var model: AppModel
    @ObservedObject private var pad = GamepadController.shared

    private func row(_ k: String, _ v: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(k).font(Theme.mono(12)).foregroundColor(Theme.ink).frame(width: 190, alignment: .leading)
            Text(v).font(Theme.text(13)).foregroundColor(Theme.muted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Eyebrow("Einstellungen · Controller")
            AccentTitle(plain: "Gamepad ", accent: "anschließen", size: 30)
            Text(model.controllerName.map { "Verbunden: \($0)" } ?? "Kein Controller verbunden. Xbox, PlayStation oder MFi per Bluetooth oder Kabel anschließen, die Tastatur geht immer.")
                .font(Theme.text(13)).foregroundColor(model.controllerName == nil ? Theme.muted : Theme.accentStrong)
            VStack(alignment: .leading, spacing: 6) {
                row("Linker Stick / Steuerkreuz", "Fliegen (Stick dosiert Schub und Fahrt)")
                row("A / Kreuz", "Löschwasser; im Menü bestätigen")
                row("B / Kreis", "Im Menü zurück")
                row("Start / Menü", "Pause")
            }
            Divider().padding(.vertical, 4)
            Eyebrow("Bestenliste")
            HStack {
                Text("Name für neue Einträge").font(Theme.mono(12)).foregroundColor(Theme.ink).frame(width: 190, alignment: .leading)
                TextField("Pilot", text: $model.playerName)
                    .textFieldStyle(.plain).font(Theme.text(13)).foregroundColor(Theme.ink)
                    .padding(.horizontal, 8).padding(.vertical, 5).frame(width: 180)
                    .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(Theme.line, lineWidth: 1))
                    .onChange(of: model.playerName) { _, v in
                        if v.count > HighScores.maxNameLength { model.playerName = String(v.prefix(HighScores.maxNameLength)) }
                        model.nameConfirmed = true
                    }
            }
            HStack {
                Text("Totzone des Sticks").font(Theme.mono(12)).foregroundColor(Theme.ink).frame(width: 190, alignment: .leading)
                Slider(value: Binding(get: { pad.deadzone }, set: { pad.deadzone = $0 }), in: 0.05...0.4)
                    .frame(width: 180)
                Text(String(format: "%.0f %%", pad.deadzone * 100)).font(Theme.mono(12)).foregroundColor(Theme.muted)
            }
        }
        .padding(24)
        .frame(width: 560, alignment: .leading)
        .background(Theme.bg)
    }
}
