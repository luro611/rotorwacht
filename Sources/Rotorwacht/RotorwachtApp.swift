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
