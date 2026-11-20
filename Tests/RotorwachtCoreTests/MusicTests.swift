import Testing
import Foundation
@testable import RotorwachtCore

/// 0.5.0 music: determinism, scales, intensity, and offline rendering with level, silence and click checks.
/// (What it sounds like can only be judged by ear.)
@Suite struct MusicTests {
    static let sr = 22050.0

    struct Stats {
        var peak: Float = 0
        var rms: Float = 0
        var maxStep: Float = 0          // largest jump between neighbouring samples
        var quietSeconds = 0            // seconds whose RMS is below the silence threshold
        var samples: [Float] = []
    }

    /// Renders mono-summed stereo output in blocks of odd size (so block borders are tested too).
    static func render(_ mixer: MusicMixer, seconds: Double, block: Int = 441,
                       at: (Double) -> Void = { _ in }) -> (l: [Float], r: [Float]) {
        var l = [Float](), r = [Float]()
        var bl = [Float](repeating: 0, count: block), br = [Float](repeating: 0, count: block)
        let total = Int(seconds * sr)
        var done = 0
        while done < total {
            at(Double(done) / sr)
            let n = min(block, total - done)
            bl.withUnsafeMutableBufferPointer { pl in br.withUnsafeMutableBufferPointer { pr in
                mixer.render(left: pl.baseAddress!, right: pr.baseAddress!, frames: n)
            } }
            l += bl[0..<n]; r += br[0..<n]
            done += n
        }
        return (l, r)
    }

    static func stats(_ x: (l: [Float], r: [Float]), from: Double = 0) -> Stats {
        var s = Stats()
        let start = Int(from * sr)
        var sum: Double = 0
        var secSum: Double = 0, secN = 0
        var prevL: Float = x.l[start], prevR: Float = x.r[start]
        for i in start..<x.l.count {
            let a = x.l[i], b = x.r[i]
            s.peak = max(s.peak, abs(a), abs(b))
            s.maxStep = max(s.maxStep, abs(a - prevL), abs(b - prevR))
            prevL = a; prevR = b
            let e = Double(a * a + b * b) / 2
            sum += e; secSum += e; secN += 1
            if secN == Int(sr) {
                if (secSum / Double(secN)).squareRoot() < 0.004 { s.quietSeconds += 1 }
                secSum = 0; secN = 0
            }
        }
        s.rms = Float((sum / Double(x.l.count - start)).squareRoot())
        return s
    }

    func mixer(_ theme: MusicTheme, intensity: Double, volume: Double = 1) -> MusicMixer {
        let m = MusicMixer(sampleRate: Self.sr)
        m.setUser(enabled: true, volume: volume)
        m.play(theme, intensity: intensity, crossfade: 0.1)
        return m
    }

    // MARK: Logic

    @Test func everyMissionHasItsOwnTheme() throws {
        var seen = Set<MusicTheme>()
        for id in MissionLibrary.all {
            let t = MusicTheme.forMission(id)
            #expect(t != .menu, "mission \(id) has no theme")
            #expect(seen.insert(t).inserted, "theme of \(id) is used twice")
        }
        #expect(MusicTheme.forMission("unbekannt") == .menu)
    }

    @Test func sameSeedSameMusicDifferentSeedDifferentMelody() {
        for t in MusicTheme.allCases {
            let a = MusicScore(theme: t, seed: 42).allNotes
            let b = MusicScore(theme: t, seed: 42).allNotes
            #expect(a == b)
        }
        let melody = { (seed: UInt64) in MusicScore(theme: .hochwasser, seed: seed).allNotes.filter { $0.layer == .lead }.map(\.midi) }
        #expect(melody(1) != melody(2))
    }

    @Test func themesDifferInKeySpeedAndMelody() {
        let loops = MusicTheme.allCases.filter(\.loops)
        var melodies = Set<[Int]>()
        for t in loops {
            melodies.insert(MusicScore(theme: t).allNotes.filter { $0.layer == .lead }.map(\.midi))
        }
        #expect(melodies.count == loops.count)
        #expect(Set(loops.map { $0.spec.bpm }).count >= 6)
    }

    @Test func allNotesStayInTheScaleOfTheTheme() {
        for t in MusicTheme.allCases {
            let score = MusicScore(theme: t)
            for n in score.allNotes where n.layer != .pulse {
                #expect(score.scaleClasses.contains(n.midi % 12), "\(t): note \(n.midi) is outside the scale")
                #expect(n.midi >= 20 && n.midi <= 110)
                #expect(n.step + 1 <= 16 && n.length >= 1)
            }
        }
    }

    @Test func layersSwitchOnWithIntensity() {
        let score = MusicScore(theme: .waldbrand)
        func count(_ i: Double, _ layer: MusicLayer) -> Int { score.allNotes.filter { $0.layer == layer && $0.minIntensity <= i }.count }
        #expect(count(0.1, .pad) > 0 && count(0.1, .lead) > 0)
        #expect(count(0.1, .pulse) == 0 && count(0.1, .high) == 0 && count(0.1, .arp) == 0)
        #expect(count(0.6, .arp) > 0 && count(0.6, .pulse) > 0)
        #expect(count(1, .high) > 0)
        let total = { (i: Double) in score.allNotes.filter { $0.minIntensity <= i }.count }
        #expect(total(0.1) < total(0.5) && total(0.5) < total(0.9))
    }

    @Test func intensityRisesWithPressureAndFallsSlowly() {
        var calm = MusicInputs()
        #expect(IntensityTracker.target(calm) == IntensityTracker.calm)
        var late = calm; late.timeUsed = 0.95
        var dry = calm; dry.fuel = 0.05
        var wet = calm; wet.flood = 1
        var burning = calm; burning.fire = 1
        for s in [late, dry, wet, burning] { #expect(IntensityTracker.target(s) > 0.4) }
        var all = calm; all.timeUsed = 1; all.fuel = 0; all.flood = 1; all.fire = 1; all.durability = 0; all.crashed = true
        #expect(IntensityTracker.target(all) <= 1)
        #expect(IntensityTracker.target(all) > 0.95)

        var t = IntensityTracker()
        for _ in 0..<100 { t.update(calm, dt: 0.1) }
        #expect(t.value < 0.2)
        for _ in 0..<40 { t.update(late, dt: 0.1) }     // 4 s of pressure
        let high = t.value
        #expect(high > 0.45)
        for _ in 0..<20 { t.update(calm, dt: 0.1) }     // 2 s later it is still high
        #expect(t.value > high * 0.6)
        calm.lost = 1; calm.durability = 0.7            // a loss and a hit: surge
        var u = IntensityTracker(); u.update(MusicInputs(), dt: 0.1)
        u.update(calm, dt: 0.1)
        #expect(u.alarm > 0.5)
    }

    @Test func settingsAreClamped() {
        var s = SoundSettings(); s.musicVolume = 3; s.effectsVolume = -1
        #expect(s.clamped.musicVolume == 1 && s.clamped.effectsVolume == 0)
        #expect(SoundSettings().musicOn)
    }

    @Test func endingsFollowTheResult() {
        func result(_ o: MissionOutcome, stars: Int) -> MissionResult {
            MissionResult(outcome: o, total: 10, rescued: 5, lost: 5, injured: 0, timeUsed: 100, helicoptersLost: 0, score: 100, stars: stars)
        }
        #expect(MusicTheme.ending(for: result(.completed, stars: 2)) == .win)
        #expect(MusicTheme.ending(for: result(.completed, stars: 0)) == .lose)
        #expect(MusicTheme.ending(for: result(.timeUp, stars: 1)) == .lose)
        #expect(MusicTheme.ending(for: result(.failed, stars: 0)) == .lose)
    }

    // MARK: Offline rendering

    @Test func renderingIsDeterministic() {
        let a = Self.render(mixer(.altstadt, intensity: 0.6), seconds: 3)
        let b = Self.render(mixer(.altstadt, intensity: 0.6), seconds: 3)
        #expect(a.l == b.l && a.r == b.r)
    }

    @Test func levelsStayCleanForEveryThemeAndIntensity() {
        for t in MusicTheme.allCases where t.loops {
            for i in [0.12, 0.5, 1.0] {
                let out = Self.render(mixer(t, intensity: i), seconds: 14)
                let s = Self.stats(out, from: 1)
                #expect(s.peak < 0.95, "\(t) @\(i): peak \(s.peak)")
                #expect(s.peak > 0.08, "\(t) @\(i): too quiet, peak \(s.peak)")
                #expect(s.rms > 0.02 && s.rms < 0.3, "\(t) @\(i): rms \(s.rms)")
                #expect(s.quietSeconds == 0, "\(t) @\(i): \(s.quietSeconds) silent seconds")
                #expect(s.maxStep < 0.3, "\(t) @\(i): jump \(s.maxStep)")
                print("music \(t.rawValue) @\(i): peak \(s.peak) rms \(s.rms) step \(s.maxStep)")
            }
        }
    }

    @Test func themeChangeCrossfadesWithoutClicks() {
        let m = mixer(.menu, intensity: 0.12)
        let out = Self.render(m, seconds: 12) { t in
            if abs(t - 4) < 0.011 { m.play(.waldbrand, intensity: 0.5, crossfade: 1.5) }
            if abs(t - 8) < 0.011 { m.setIntensity(1) }
        }
        let s = Self.stats(out, from: 1)
        #expect(s.peak < 0.95)
        #expect(s.maxStep < 0.3, "jump \(s.maxStep)")
        #expect(s.quietSeconds == 0)
        #expect(m.slotCount == 1, "old theme should be gone after the fade")
        #expect(m.theme == .waldbrand)
    }

    @Test func sameThemeAgainDoesNotRestart() {
        let m = mixer(.menu, intensity: 0.12)
        _ = Self.render(m, seconds: 1)
        m.play(.menu)
        #expect(m.slotCount == 1)
    }

    @Test func pauseAndResumeAreSmoothAndSilentInBetween() {
        let m = mixer(.gebirge, intensity: 0.4)
        let out = Self.render(m, seconds: 9) { t in
            if abs(t - 3) < 0.011 { m.setPaused(true) }
            if abs(t - 6) < 0.011 { m.setPaused(false) }
        }
        let s = Self.stats(out, from: 1)
        #expect(s.maxStep < 0.3, "jump \(s.maxStep)")
        // Between 3.6 s and 6 s it is completely still.
        let a = Int(3.6 * Self.sr), b = Int(5.99 * Self.sr)
        #expect(out.l[a..<b].allSatisfy { $0 == 0 } && out.r[a..<b].allSatisfy { $0 == 0 })
        // And it plays again afterwards.
        let after = Self.stats((Array(out.l[Int(7 * Self.sr)...]), Array(out.r[Int(7 * Self.sr)...])))
        #expect(after.rms > 0.02)
    }

    @Test func musicOffFadesOutAndOnFadesIn() {
        let m = mixer(.hochwasser, intensity: 0.3)
        let out = Self.render(m, seconds: 6) { t in
            if abs(t - 2) < 0.011 { m.setUser(enabled: false, volume: 1) }
            if abs(t - 4) < 0.011 { m.setUser(enabled: true, volume: 1) }
        }
        #expect(Self.stats(out).maxStep < 0.3)
        let a = Int(2.3 * Self.sr), b = Int(3.99 * Self.sr)
        #expect(out.l[a..<b].allSatisfy { $0 == 0 })
        #expect(Self.stats((Array(out.l[Int(5 * Self.sr)...]), Array(out.r[Int(5 * Self.sr)...]))).rms > 0.02)
    }

    @Test func volumeScalesTheMusic() {
        let loud = Self.stats(Self.render(mixer(.kueste, intensity: 0.5, volume: 1), seconds: 6), from: 1)
        let soft = Self.stats(Self.render(mixer(.kueste, intensity: 0.5, volume: 0.5), seconds: 6), from: 1)
        #expect(soft.rms < loud.rms * 0.4 && soft.rms > loud.rms * 0.1)
    }

    @Test func endingsPlayOnceThenGoSilent() {
        for t in [MusicTheme.win, .lose] {
            let m = MusicMixer(sampleRate: Self.sr)
            m.setUser(enabled: true, volume: 1)
            m.play(.vulkan, intensity: 0.8, crossfade: 0.1)
            _ = Self.render(m, seconds: 2)
            m.play(t, crossfade: 0.6)
            let out = Self.render(m, seconds: 22)
            let s = Self.stats(out, from: 2)
            #expect(s.peak < 0.95)
            #expect(s.maxStep < 0.3, "\(t): jump \(s.maxStep)")
            #expect(s.rms > 0.01, "\(t) not audible")
            // Starts audibly within a second, and is quiet again before the end.
            let early = Self.stats((Array(out.l[Int(2.5 * Self.sr)..<Int(6 * Self.sr)]), Array(out.r[Int(2.5 * Self.sr)..<Int(6 * Self.sr)])))
            #expect(early.rms > 0.02, "\(t) silent at the start")
            let late = out.l[Int(20 * Self.sr)...]
            #expect(late.allSatisfy { abs($0) < 0.001 }, "\(t) does not end")
            #expect(m.slotCount == 0, "\(t) was not removed")
        }
    }

    @Test func busierIntensityIsLouderAndDenser() {
        let calm = Self.stats(Self.render(mixer(.waldbrand, intensity: 0.12), seconds: 10), from: 2)
        let tense = Self.stats(Self.render(mixer(.waldbrand, intensity: 1), seconds: 10), from: 2)
        #expect(tense.rms > calm.rms)
    }
}
