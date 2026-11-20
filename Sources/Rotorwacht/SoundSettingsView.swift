import SwiftUI
import RotorwachtCore

/// Music on/off and the two volumes. Used in the start menu and in the pause card.
struct SoundSettingsView: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        HStack(spacing: 18) {
            Eyebrow("Ton")
            Button(model.sound.musicOn ? "Musik an" : "Musik aus") { model.sound.musicOn.toggle() }
                .buttonStyle(LevelButtonStyle(selected: model.sound.musicOn))
                .accessibilityLabel("Musik ein- oder ausschalten")
            slider("Musik", value: $model.sound.musicVolume).opacity(model.sound.musicOn ? 1 : 0.4)
            slider("Effekte", value: $model.sound.effectsVolume)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        HStack(spacing: 8) {
            Text(title).font(Theme.text(12)).foregroundColor(Theme.muted)
            Slider(value: value, in: 0...1).tint(Theme.accent).frame(width: 110)
                .accessibilityLabel("Lautstärke \(title)")
        }
    }
}
