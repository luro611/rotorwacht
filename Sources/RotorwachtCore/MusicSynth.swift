import Foundation

/// Plays one `MusicScore` as samples: sequencer, a handful of simple voices, a small stereo echo and a soft limiter.
/// Pure arithmetic, no system calls, so it can run on the audio thread and in tests (offline rendering).
/// Nothing is allocated while rendering.
public final class MusicSynth {
    private enum Kind { case pad, bass, bell, flute, pluck, brass, arp, kick, tick, high }

    private struct Voice {
        var active = false
        var kind: Kind = .pad
        var freq: Float = 0
        var ph1: Float = 0, ph2: Float = 0, ph3: Float = 0
        var env: Float = 0
        var attackRate: Float = 0.01
        var releaseRate: Float = 0.001
        var gate = 0
        var releasing = false
        var amp: Float = 1
        var decay: Float = 1
        var percussive = false
        var vel: Float = 0
        var panL: Float = 0.7, panR: Float = 0.7
        var lp: Float = 0
        var cutoff: Float = 0.1
        var t: Float = 0
    }

    public let score: MusicScore
    public let sampleRate: Float
    private static let maxVoices = 32
    private var voices = [Voice](repeating: Voice(), count: maxVoices)

    // Sequencer
    private var bar = 0
    private var step = 0
    private var untilStep: Float = 0
    private var sequenceDone = false
    private var tailSamples = 0

    // Control (written from the main thread, read by the audio thread; single numbers, a race only costs a few samples)
    /// Wanted intensity 0...1; the sound follows with a delay of a second or so.
    public var intensityTarget: Double = 0.15
    private var intensity: Float = 0.15
    /// Level of this synth in the mix, ramped linearly.
    public private(set) var gain: Float = 0
    private var gainTarget: Float = 0
    private var gainStep: Float = 0.001
    private var rng: UInt32 = 0x2545_F491

    // Echo
    private var delayL: [Float], delayR: [Float]
    private var dI = 0, dJ = 0
    private var echoLP: (Float, Float) = (0, 0)

    /// Overall level before the limiter.
    public var master: Float = 0.42

    /// A stinger that has played to its end and died away (looping themes never finish).
    public var finished: Bool { sequenceDone && tailSamples > Int(sampleRate * 3) }
    /// Time in seconds since the start (for tests and fades).
    public private(set) var position: Double = 0

    public init(theme: MusicTheme, seed: UInt64? = nil, sampleRate: Double = 44100, startIntensity: Double = 0.15) {
        score = MusicScore(theme: theme, seed: seed)
        self.sampleRate = Float(sampleRate)
        delayL = [Float](repeating: 0, count: max(8, Int(sampleRate * 0.29)))
        delayR = [Float](repeating: 0, count: max(8, Int(sampleRate * 0.37)))
        intensityTarget = startIntensity
        intensity = Float(startIntensity)
        rng ^= UInt32(truncatingIfNeeded: score.seed)
        if rng == 0 { rng = 1 }
    }

    /// Fade the level to `level` over `seconds` (never a jump).
    public func fade(to level: Float, seconds: Double) {
        gainTarget = level
        let n = max(1, Float(seconds) * sampleRate)
        gainStep = max(1 / n, 1e-6)
        if seconds <= 0 { gainStep = 1 }
    }
    public var gainGoal: Float { gainTarget }

    private func noise() -> Float {
        rng ^= rng << 13; rng ^= rng >> 17; rng ^= rng << 5
        return Float(Int32(bitPattern: rng)) / Float(Int32.max)
    }

    // MARK: Sequencer

    private func stepSamples() -> Float {
        sampleRate * 60 / Float(score.bpm * 4) / (1 + 0.14 * intensity)
    }

    private func advanceStep() {
        if !sequenceDone {
            for n in score.notes(bar: bar, step: step) where Float(n.minIntensity) <= intensity + 0.0001 {
                trigger(n)
            }
            step += 1
            if step == MusicScore.stepsPerBar {
                step = 0
                bar += 1
                if bar >= score.bars {
                    if score.loops { bar = 0 } else { sequenceDone = true }
                }
            }
        }
        untilStep += stepSamples()
    }

    private func trigger(_ n: MusicNote) {
        guard let i = voices.firstIndex(where: { !$0.active }) else { return } // full: skip the note
        let sr = sampleRate
        var v = Voice()
        v.active = true
        v.freq = 440 * powf(2, Float(n.midi - 69) / 12)
        v.vel = n.velocity * (0.8 + 0.2 * intensity)
        let pan = Float((n.midi * 7) % 13) / 13 - 0.5
        v.panL = 0.7 - pan * 0.5
        v.panR = 0.7 + pan * 0.5
        let stepLen = stepSamples()
        v.gate = max(1, Int(Float(n.length) * stepLen))
        func attack(_ s: Float) -> Float { 1 / max(Float(0.004) * sr, s * sr) }   // never shorter than 4 ms
        func release(_ s: Float) -> Float { 1 / max(Float(0.015) * sr, s * sr) }  // never shorter than 15 ms
        func decayPerSample(_ tau: Float) -> Float { expf(-1 / (tau * sr)) }
        let bright = score.brightness * (0.6 + 0.8 * intensity)
        func lowpass(_ fc: Float) -> Float { 1 - expf(-2 * .pi * min(fc, sr * 0.4) / sr) }
        switch n.layer {
        case .pad:
            v.kind = .pad
            v.attackRate = attack(0.45); v.releaseRate = release(0.9)
            v.cutoff = lowpass(500 + 2600 * bright)
            v.ph2 = Float(i % 7) / 7
        case .bass:
            v.kind = .bass
            v.attackRate = attack(0.01); v.releaseRate = release(0.09)
            v.cutoff = lowpass(420)
        case .lead:
            switch score.timbre {
            case .bell:
                v.kind = .bell; v.attackRate = attack(0.004); v.releaseRate = release(0.5)
                v.gate = Int(Float(max(n.length, 4)) * stepLen); v.percussive = true; v.decay = decayPerSample(1.4)
            case .flute:
                v.kind = .flute; v.attackRate = attack(0.05); v.releaseRate = release(0.28)
                v.cutoff = lowpass(2400)
            case .pluck:
                v.kind = .pluck; v.attackRate = attack(0.004); v.releaseRate = release(0.1)
                v.percussive = true; v.decay = decayPerSample(0.32); v.cutoff = lowpass(2800)
            case .brass:
                v.kind = .brass; v.attackRate = attack(0.07); v.releaseRate = release(0.18)
                v.cutoff = lowpass(900 + 1500 * bright)
            }
        case .arp:
            v.kind = .arp; v.attackRate = attack(0.004); v.releaseRate = release(0.08)
            v.percussive = true; v.decay = decayPerSample(0.2)
        case .pulse:
            if n.midi == 0 {
                v.kind = .kick; v.attackRate = attack(0.002); v.releaseRate = release(0.05)
                v.percussive = true; v.decay = decayPerSample(0.13); v.gate = Int(sr * 0.4)
            } else {
                v.kind = .tick; v.attackRate = attack(0.002); v.releaseRate = release(0.02)
                v.percussive = true; v.decay = decayPerSample(0.03); v.gate = Int(sr * 0.12)
            }
        case .high:
            v.kind = .high; v.attackRate = attack(0.004); v.releaseRate = release(0.04)
            v.percussive = true; v.decay = decayPerSample(0.09); v.gate = Int(sr * 0.2)
        }
        voices[i] = v
    }

    // MARK: Voices

    @inline(__always) private func saw(_ p: Float) -> Float { 2 * p - 1 }
    @inline(__always) private func tri(_ p: Float) -> Float { 4 * abs(p - 0.5) - 1 }

    /// One sample of a voice, enveloped, plus the end-of-life handling.
    private func voiceSample(_ v: inout Voice) -> Float {
        let inv = 1 / sampleRate
        var s: Float
        switch v.kind {
        case .pad:
            v.ph1 += v.freq * 0.9985 * inv; v.ph1 -= floorf(v.ph1)
            v.ph2 += v.freq * 1.0015 * inv; v.ph2 -= floorf(v.ph2)
            v.lp += (0.5 * (saw(v.ph1) + saw(v.ph2)) - v.lp) * v.cutoff
            s = v.lp * 0.5
        case .bass:
            v.ph1 += v.freq * inv; v.ph1 -= floorf(v.ph1)
            v.lp += (saw(v.ph1) - v.lp) * v.cutoff
            s = sinf(2 * .pi * v.ph1) * 0.8 + v.lp * 0.3
        case .bell:
            v.ph1 += v.freq * inv; v.ph1 -= floorf(v.ph1)
            v.ph2 += v.freq * 2.76 * inv; v.ph2 -= floorf(v.ph2)
            s = sinf(2 * .pi * v.ph1) * 0.7 + sinf(2 * .pi * v.ph2) * 0.22 * v.amp
        case .flute:
            v.t += inv
            let vib = 1 + 0.004 * sinf(2 * .pi * 5.2 * v.t) * min(1, v.t * 2)
            v.ph1 += v.freq * vib * inv; v.ph1 -= floorf(v.ph1)
            v.lp += (tri(v.ph1) - v.lp) * v.cutoff
            s = v.lp * 0.6 + sinf(2 * .pi * v.ph1) * 0.35
        case .pluck:
            v.ph1 += v.freq * inv; v.ph1 -= floorf(v.ph1)
            let c = v.cutoff * (0.25 + 0.75 * v.amp)
            v.lp += (saw(v.ph1) - v.lp) * c
            s = v.lp * 0.55
        case .brass:
            v.ph1 += v.freq * 0.997 * inv; v.ph1 -= floorf(v.ph1)
            v.ph2 += v.freq * 1.003 * inv; v.ph2 -= floorf(v.ph2)
            v.lp += (0.5 * (saw(v.ph1) + saw(v.ph2)) - v.lp) * v.cutoff * (0.5 + 0.5 * min(1, v.env))
            s = v.lp * 0.55
        case .arp:
            v.ph1 += v.freq * inv; v.ph1 -= floorf(v.ph1)
            s = tri(v.ph1) * 0.5 + sinf(2 * .pi * v.ph1) * 0.3
        case .kick:
            v.t += inv
            let f = 46 + 90 * expf(-v.t * 28)
            v.ph1 += f * inv; v.ph1 -= floorf(v.ph1)
            s = sinf(2 * .pi * v.ph1) * 0.9
        case .tick:
            let n = noise()
            v.lp += (n - v.lp) * 0.55
            s = (n - v.lp) * 0.5
        case .high:
            v.ph1 += v.freq * inv; v.ph1 -= floorf(v.ph1)
            s = sinf(2 * .pi * v.ph1) * 0.6
        }
        // Envelope: linear attack, hold for the gate, linear release; percussive voices also decay on their own.
        if v.gate > 0 {
            v.gate -= 1
            if v.gate == 0 { v.releasing = true }
        }
        if v.releasing {
            v.env -= v.releaseRate
            if v.env <= 0 { v.env = 0; v.active = false }
        } else if v.env < 1 {
            v.env = min(1, v.env + v.attackRate)
        }
        if v.percussive {
            v.amp *= v.decay
            if v.amp < 0.0006 { v.active = false }
        }
        return s * v.env * v.amp * v.vel
    }

    // MARK: Render

    /// Adds `frames` samples of this synth, times its fade level, to the two buffers.
    public func render(left: UnsafeMutablePointer<Float>, right: UnsafeMutablePointer<Float>, frames: Int) {
        if gain == 0 && gainTarget == 0 { return } // fully faded out: costs nothing
        let ti = Float(intensityTarget)
        let k = 1 - expf(-1 / (1.3 * sampleRate))
        for f in 0..<frames {
            // Level ramp
            if gain != gainTarget {
                let d = gainTarget - gain
                gain += abs(d) <= gainStep ? d : (d > 0 ? gainStep : -gainStep)
            }
            intensity += (ti - intensity) * k
            untilStep -= 1
            if untilStep <= 0 { advanceStep() }

            var dl: Float = 0, dr: Float = 0   // pitched voices, go through the echo
            var pl: Float = 0, pr: Float = 0   // percussion, stays dry
            var live = 0
            for i in 0..<Self.maxVoices where voices[i].active {
                live += 1
                let kind = voices[i].kind
                let s = voiceSample(&voices[i])
                let l = s * voices[i].panL, r = s * voices[i].panR
                if kind == .kick || kind == .tick { pl += l; pr += r } else { dl += l; dr += r }
            }
            if sequenceDone && live == 0 { tailSamples += 1 }

            // Echo with crossed feedback
            let wl = delayL[dI], wr = delayR[dJ]
            echoLP.0 += (wl - echoLP.0) * 0.35
            echoLP.1 += (wr - echoLP.1) * 0.35
            let nl = dl + echoLP.1 * 0.42, nr = dr + echoLP.0 * 0.42
            delayL[dI] = abs(nl) < 1e-12 ? 0 : nl
            delayR[dJ] = abs(nr) < 1e-12 ? 0 : nr
            dI += 1; if dI == delayL.count { dI = 0 }
            dJ += 1; if dJ == delayR.count { dJ = 0 }

            let ml = (dl + wl * 0.3 + pl) * master
            let mr = (dr + wr * 0.3 + pr) * master
            left[f] += tanhf(ml) * gain
            right[f] += tanhf(mr) * gain
        }
        position += Double(frames) / Double(sampleRate)
    }
}
