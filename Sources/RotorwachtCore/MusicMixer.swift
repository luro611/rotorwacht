import Foundation

/// Mixes the music: crossfades between themes, plays the short endings, applies the player's volume
/// and on/off switch and pauses cleanly. All level changes are ramps, so nothing clicks.
/// `render` is meant for the audio thread; the other calls come from the main thread.
public final class MusicMixer {
    public let sampleRate: Double
    private let lock = NSLock()
    private var slots: [MusicSynth] = []
    private static let maxSlots = 4

    // Level chain: user volume and pause each ramp separately.
    private var userGain: Float = 0
    private var userTarget: Float = 0
    private var pauseGain: Float = 1
    private var pauseTarget: Float = 1
    private var userStep: Float
    private var pauseStep: Float
    private var currentTheme: MusicTheme?

    public init(sampleRate: Double) {
        self.sampleRate = sampleRate
        userStep = 1 / Float(0.06 * sampleRate)
        pauseStep = 1 / Float(0.35 * sampleRate)
    }

    public var theme: MusicTheme? { lock.lock(); defer { lock.unlock() }; return currentTheme }
    public var slotCount: Int { lock.lock(); defer { lock.unlock() }; return slots.count }

    /// Starts a theme. A running theme fades out over `crossfade` seconds while the new one fades in.
    /// The same theme again is ignored (so the menu does not restart).
    public func play(_ theme: MusicTheme, seed: UInt64? = nil, intensity: Double = 0.15, crossfade: Double = 1.5) {
        lock.lock()
        if currentTheme == theme, theme.loops, slots.last.map({ $0.gainGoal > 0 }) == true { lock.unlock(); return }
        let synth = MusicSynth(theme: theme, seed: seed, sampleRate: sampleRate, startIntensity: theme.loops ? intensity : 0)
        for s in slots { s.fade(to: 0, seconds: crossfade) }
        // A new theme starts quietly under the old one; a short ending comes in at once.
        synth.fade(to: 1, seconds: theme.loops ? crossfade : 0.05)
        slots.append(synth)
        while slots.count > Self.maxSlots { slots.removeFirst() }
        currentTheme = theme
        lock.unlock()
    }

    /// Fades everything out and stays silent.
    public func stop(fade: Double = 0.8) {
        lock.lock()
        for s in slots { s.fade(to: 0, seconds: fade) }
        currentTheme = nil
        lock.unlock()
    }

    /// Intensity 0...1 for the running theme (the sound follows slowly).
    public func setIntensity(_ value: Double) {
        lock.lock()
        if let s = slots.last, s.score.loops { s.intensityTarget = min(1, max(0, value)) }
        lock.unlock()
    }

    /// Player settings: `volume` 0...1 (perceptual curve applied here).
    public func setUser(enabled: Bool, volume: Double) {
        let v = Float(min(1, max(0, volume)))
        lock.lock(); userTarget = enabled ? v * v : 0; lock.unlock()
    }

    /// Pause: music fades out and stands still; resuming fades back in at the same place.
    public func setPaused(_ paused: Bool) {
        lock.lock(); pauseTarget = paused ? 0 : 1; lock.unlock()
    }

    /// True once everything is silent (no slot, or all faded out, or music switched off).
    public var isSilent: Bool {
        lock.lock(); defer { lock.unlock() }
        return slots.allSatisfy { $0.gain == 0 && $0.gainGoal == 0 } || userGain == 0 && userTarget == 0
    }

    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        for i in 0..<frames { left[i] = 0; right[i] = 0 }
        lock.lock()
        defer { lock.unlock() }
        // Paused and faded out (or switched off): standing still, no sequencer moves.
        let silentByUser = userGain == 0 && userTarget == 0
        let silentByPause = pauseGain == 0 && pauseTarget == 0
        if !silentByUser && !silentByPause {
            for s in slots { s.render(left: left, right: right, frames: frames) }
        }
        // Chain gains, per sample. Rendering a silent chain is skipped above; here the ramps still run.
        for i in 0..<frames {
            if userGain != userTarget {
                let d = userTarget - userGain
                userGain += abs(d) <= userStep ? d : (d > 0 ? userStep : -userStep)
            }
            if pauseGain != pauseTarget {
                let d = pauseTarget - pauseGain
                pauseGain += abs(d) <= pauseStep ? d : (d > 0 ? pauseStep : -pauseStep)
            }
            let g = userGain * pauseGain
            left[i] *= g
            right[i] *= g
        }
        // Drop slots that are completely faded out, and stingers that have died away.
        if !silentByPause {
            slots.removeAll { ($0.gain == 0 && $0.gainGoal == 0) || $0.finished }
            if slots.isEmpty { currentTheme = nil }
        }
    }
}
