import AVFoundation
import RotorwachtCore

/// Plays the procedural music (`MusicMixer` in RotorwachtCore) through its own audio engine, apart from the
/// effects of `AudioEngine`, so music and effect volumes are independent. Without an audio device it stays silent.
final class MusicPlayer {
    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode?
    private(set) var mixer: MusicMixer
    private var observer: NSObjectProtocol?

    init() {
        let out = engine.outputNode.outputFormat(forBus: 0)
        let rate = out.sampleRate > 0 ? out.sampleRate : 44100
        mixer = MusicMixer(sampleRate: rate)
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2) else { return }
        let mixer = self.mixer
        let node = AVAudioSourceNode(format: fmt) { _, _, frames, abl in
            let buffers = UnsafeMutableAudioBufferListPointer(abl)
            guard buffers.count >= 2,
                  let l = buffers[0].mData?.assumingMemoryBound(to: Float.self),
                  let r = buffers[1].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
            mixer.render(left: l, right: r, frames: Int(frames))
            return noErr
        }
        source = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        // Headphones plugged in or the output device changed: the engine stops by itself, start it again.
        observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            try? self?.engine.start()
        }
    }

    deinit { if let o = observer { NotificationCenter.default.removeObserver(o) }; engine.stop() }

    func start() {
        guard !engine.isRunning else { return }
        try? engine.start()
    }

    func play(_ theme: MusicTheme, seed: UInt64? = nil, crossfade: Double = 1.5) {
        mixer.play(theme, seed: seed, intensity: IntensityTracker.calm, crossfade: crossfade)
    }
    func stop() { mixer.stop() }
    func setIntensity(_ v: Double) { mixer.setIntensity(v) }
    func setPaused(_ p: Bool) { mixer.setPaused(p) }
    func apply(_ s: SoundSettings) { mixer.setUser(enabled: s.musicOn, volume: s.musicVolume) }
}
