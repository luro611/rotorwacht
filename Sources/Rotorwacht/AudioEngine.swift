import AVFoundation

enum SFX { case ding, rescued, thump(Float), alarm, splash, warn, crash, ignite, hiss, thunder(Float), rumble, pop }

/// Synthesised sound: rotor, wind and short signal tones. No sound files, nothing to license.
final class AudioEngine {
    private struct Voice { var kind: SFX; var t: Float = 0; var amp: Float = 1 }

    private let engine = AVAudioEngine()
    private var source: AVAudioSourceNode!
    private let lock = NSLock()
    // Fixed storage: nothing is allocated on the audio thread.
    private static let maxVoices = 16
    private var pending = [Voice](repeating: Voice(kind: .ding), count: maxVoices)
    private var pendingCount = 0
    private var active = [Voice](repeating: Voice(kind: .ding), count: maxVoices)
    private var activeCount = 0
    private var sampleRate: Float = 44100

    // Written from the main thread, read by the audio thread (single floats; fine for this purpose).
    var thrust: Float = 0
    var rotorSpeed: Float = 0
    var wind: Float = 0
    /// Loudness of nearby fire (crackle and roar), 0...1.
    var fire: Float = 0
    /// 1 while water is being released, 0...1.
    var spray: Float = 0
    /// 1 while the tank is filling, 0...1.
    var fill: Float = 0
    var enabled = true
    /// Effect volume from the settings, 0...1.
    var volume: Float = 1 { didSet { engine.mainMixerNode.outputVolume = 0.6 * min(1, max(0, volume)) } }

    // Audio-thread state
    private var chopPhase: Float = 0
    private var rumblePhase: Float = 0
    private var lp1: Float = 0, lp2: Float = 0, windLP: Float = 0
    private var rng: UInt32 = 0x1234_5678
    private var smoothRotor: Float = 0, smoothThrust: Float = 0, smoothWind: Float = 0
    private var smoothFire: Float = 0, smoothSpray: Float = 0, smoothFill: Float = 0
    private var fireLP: Float = 0, sprayLP: Float = 0, crackle: Float = 0

    init() {
        let out = engine.outputNode.outputFormat(forBus: 0)
        sampleRate = out.sampleRate > 0 ? Float(out.sampleRate) : 44100
        guard let fmt = AVAudioFormat(standardFormatWithSampleRate: Double(sampleRate), channels: 1) else { return }
        source = AVAudioSourceNode(format: fmt) { [unowned self] _, _, frames, abl in
            self.render(Int(frames), abl)
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: fmt)
        engine.mainMixerNode.outputVolume = 0.6
    }

    func start() {
        guard !engine.isRunning else { return }
        try? engine.start() // No audio device? The game stays silent.
    }

    func stop() {
        engine.stop()
        if source != nil { engine.detach(source); source = nil }
    }

    deinit { stop() }

    func play(_ kind: SFX) {
        guard enabled else { return }
        lock.lock(); defer { lock.unlock() }
        if pendingCount < Self.maxVoices { pending[pendingCount] = Voice(kind: kind); pendingCount += 1 }
    }

    private func noise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }

    private func render(_ frames: Int, _ abl: UnsafeMutablePointer<AudioBufferList>) {
        let buffers = UnsafeMutableAudioBufferListPointer(abl)
        guard let buf = buffers.first, let data = buf.mData?.assumingMemoryBound(to: Float.self) else { return }
        let dt = 1 / sampleRate
        let targetRotor = enabled ? rotorSpeed : 0
        let targetThrust = thrust, targetWind = enabled ? wind : 0
        let targetFire = enabled ? fire : 0, targetSpray = enabled ? spray : 0, targetFill = enabled ? fill : 0

        if lock.try() {
            for i in 0..<pendingCount where activeCount < Self.maxVoices { active[activeCount] = pending[i]; activeCount += 1 }
            pendingCount = 0
            lock.unlock()
        }

        for i in 0..<frames {
            smoothRotor += (targetRotor - smoothRotor) * 0.0004
            smoothThrust += (targetThrust - smoothThrust) * 0.0006
            smoothWind += (targetWind - smoothWind) * 0.0004
            smoothFire += (targetFire - smoothFire) * 0.0003
            smoothSpray += (targetSpray - smoothSpray) * 0.002
            smoothFill += (targetFill - smoothFill) * 0.002

            // Rotor: blade-pass chop (noise shaped by a pulse) plus a low engine tone.
            let chopHz = 10 + 7 * smoothThrust
            chopPhase += chopHz * dt; if chopPhase > 1 { chopPhase -= 1 }
            let pulse = powf(max(0, sinf(2 * .pi * chopPhase)), 2)
            let n = noise()
            lp1 += (n - lp1) * (0.05 + 0.04 * smoothThrust)
            lp2 += (lp1 - lp2) * 0.2
            var s = lp2 * (0.15 + 0.85 * pulse) * 1.6 * smoothRotor * (0.45 + 0.35 * smoothThrust)
            rumblePhase += (48 + 26 * smoothThrust) * dt; if rumblePhase > 1 { rumblePhase -= 1 }
            s += sinf(2 * .pi * rumblePhase) * 0.07 * smoothRotor
            s += sinf(2 * .pi * rumblePhase * 3.01) * 0.02 * smoothRotor

            // Wind
            windLP += (n - windLP) * 0.02
            s += windLP * smoothWind * 0.6

            // Fire: low roar plus sharp crackles at random moments.
            if smoothFire > 0.001 {
                fireLP += (n - fireLP) * 0.012
                if abs(noise()) > 0.9985 - 0.004 * smoothFire { crackle = 1 }
                crackle *= 0.9985
                s += fireLP * smoothFire * 1.1 + n * crackle * crackle * smoothFire * 0.35
            }
            // Water: bright hiss while dropping, softer gurgle while filling.
            if smoothSpray > 0.001 || smoothFill > 0.001 {
                sprayLP += (n - sprayLP) * 0.25
                let hiss = n - sprayLP
                s += hiss * smoothSpray * 0.22 + (sprayLP * 0.5 + hiss * 0.2) * smoothFill * 0.14
            }

            // One-shot voices
            for v in 0..<activeCount {
                s += sample(&active[v], dt: dt, noise: n)
            }
            data[i] = max(-0.95, min(0.95, s))
        }
        var kept = 0
        for i in 0..<activeCount where !done(active[i]) {
            if kept != i { active[kept] = active[i] }
            kept += 1
        }
        activeCount = kept
    }

    private func duration(_ k: SFX) -> Float {
        switch k {
        case .ding: return 0.5
        case .rescued: return 0.9
        case .thump: return 0.6
        case .alarm: return 0.6
        case .splash: return 0.5
        case .warn: return 0.55
        case .crash: return 1.4
        case .ignite: return 0.7
        case .hiss: return 0.5
        case .thunder: return 2.6
        case .rumble: return 1.8
        case .pop: return 0.3
        }
    }
    private func done(_ v: Voice) -> Bool { v.t > duration(v.kind) }

    private func tone(_ f: Float, _ t: Float, decay: Float) -> Float {
        sinf(2 * .pi * f * t) * expf(-t * decay)
    }

    private func sample(_ v: inout Voice, dt: Float, noise n: Float) -> Float {
        let t = v.t
        v.t += dt
        switch v.kind {
        case .ding:
            return (tone(880, t, decay: 9) + 0.5 * tone(1320, t, decay: 12)) * 0.22
        case .rescued:
            var s: Float = 0
            let notes: [Float] = [523.25, 659.25, 783.99]
            for (k, f) in notes.enumerated() {
                let tt = t - Float(k) * 0.12
                if tt >= 0 { s += tone(f, tt, decay: 7) }
            }
            return s * 0.2
        case .thump(let a):
            return (sinf(2 * .pi * 58 * t) * expf(-t * 9) + n * 0.25 * expf(-t * 22)) * 0.6 * a
        case .alarm:
            let on = (t < 0.2) || (t > 0.28 && t < 0.48)
            return on ? sinf(2 * .pi * 740 * t) * 0.18 : 0
        case .splash:
            return n * expf(-t * 8) * 0.25
        case .warn:
            let f: Float = t < 0.25 ? 520 : 430
            let on = t < 0.22 || (t > 0.28 && t < 0.5)
            return on ? sinf(2 * .pi * f * t) * 0.15 : 0
        case .ignite:
            // Whoosh of a fire catching: noise swelling up, then fading.
            let env = min(1, t / 0.15) * expf(-t * 4)
            return n * env * 0.3 + sinf(2 * .pi * 70 * t) * env * 0.12
        case .hiss:
            return n * expf(-t * 7) * 0.12
        case .thunder(let a):
            // A crack, then a long low rumble.
            let crack = n * expf(-t * 30) * 0.5
            let rumble = (sinf(2 * .pi * 34 * t) * 0.5 + sinf(2 * .pi * 51 * t + 1) * 0.3 + n * 0.25) * min(1, t / 0.08) * expf(-t * 1.6)
            return (crack + rumble * 0.6) * a
        case .rumble:
            let env = min(1, t / 0.3) * expf(-t * 1.2)
            return (sinf(2 * .pi * 29 * t) * 0.35 + sinf(2 * .pi * 43 * t) * 0.2 + n * 0.12) * env * 0.6
        case .pop:
            return (sinf(2 * .pi * 150 * t * expf(-t * 6)) * expf(-t * 14) * 0.4 + n * expf(-t * 30) * 0.15)
        case .crash:
            return (sinf(2 * .pi * 42 * t) * expf(-t * 3) * 0.7 + n * expf(-t * 4) * 0.35)
        }
    }
}
