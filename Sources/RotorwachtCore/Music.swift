import Foundation

// Procedural music: scales, chord progressions, melodies and layers, all derived from a theme and a seed.
// Nothing here makes sound; `MusicSynth` turns a `MusicScore` into samples. Own compositions, no recorded
// material, nothing taken from existing pieces.

/// Tracks of the arrangement. Higher intensity switches more of them on.
public enum MusicLayer: Int, Sendable { case pad, bass, lead, arp, pulse, high }

/// Sound character of the lead voice.
public enum LeadTimbre: Sendable { case bell, flute, pluck, brass }

public struct MusicNote: Equatable, Sendable {
    /// Sixteenth step inside the bar, 0..<16.
    public var step: Int
    /// Length in sixteenths.
    public var length: Int
    /// MIDI note number. For `.pulse`: 0 = kick, 1 = tick.
    public var midi: Int
    public var velocity: Float
    public var layer: MusicLayer
    /// The note only plays once the intensity has reached this value (0...1; above 1 = never).
    public var minIntensity: Double
}

public enum MusicTheme: String, CaseIterable, Sendable {
    case menu, hochwasser, waldbrand, kueste, altstadt, vulkan, gebirge
    case bohrinsel, staudamm, passhoehe, wueste
    /// Short endings for the result screen; they play once.
    case win, lose

    public var loops: Bool { self != .win && self != .lose }

    /// Music for a mission file id; unknown ids get the calm menu theme.
    public static func forMission(_ id: String) -> MusicTheme {
        switch id {
        case "hochwasser": return .hochwasser
        case "waldbrand": return .waldbrand
        case "kueste": return .kueste
        case "altstadt": return .altstadt
        case "vulkan": return .vulkan
        case "gebirge": return .gebirge
        case "bohrinsel": return .bohrinsel
        case "staudamm": return .staudamm
        case "pass": return .passhoehe
        case "wueste": return .wueste
        default: return .menu
        }
    }

    /// The ending that fits a result: at least one star counts as success.
    public static func ending(for r: MissionResult) -> MusicTheme {
        r.outcome == .completed && r.stars >= 1 ? .win : .lose
    }

    /// Fixed seed per theme so a melody is recognisable from play to play.
    public var defaultSeed: UInt64 {
        var h: UInt64 = 0xcbf2_9ce4_8422_2325
        for b in rawValue.utf8 { h = (h ^ UInt64(b)) &* 0x100_0000_01b3 }
        return h
    }
}

/// Fixed numbers of one theme: key, scale, speed, chords, character.
struct ThemeSpec {
    var tonic: Int
    var scale: [Int]
    var bpm: Double
    /// One scale degree per bar (8 bars, then the whole thing repeats).
    var progression: [Int]
    var timbre: LeadTimbre
    /// Rhythm templates for the melody: (step, length) per note, one template per bar.
    var rhythms: [[(Int, Int)]]
    /// Register of the lead as scale index above the tonic (7 = one octave up).
    var leadBase: Int
    var pulse: Float          // 0 = no percussion, 1 = heavy
    var bassPulse: Bool       // eighth-note bass at high intensity
    var arpPattern: [Int]     // chord tone index per eighth note
    var padOctave: Int        // octaves above the tonic for the pad
    var brightness: Float     // 0...1, how open the pad sounds
}

extension MusicTheme {
    var spec: ThemeSpec {
        switch self {
        case .menu:
            return ThemeSpec(tonic: 50, scale: [0, 2, 3, 5, 7, 9, 10], bpm: 62,
                             progression: [0, 3, 5, 2, 0, 3, 4, 0], timbre: .bell,
                             rhythms: [[(0, 6), (8, 4), (12, 4)], [(0, 4), (4, 4), (8, 8)], [(2, 4), (8, 6), (14, 2)]],
                             leadBase: 7, pulse: 0, bassPulse: false, arpPattern: [0, 1, 2, 1], padOctave: 1, brightness: 0.35)
        case .hochwasser:
            return ThemeSpec(tonic: 45, scale: [0, 2, 3, 5, 7, 8, 10], bpm: 76,
                             progression: [0, 5, 2, 6, 0, 3, 6, 4], timbre: .flute,
                             rhythms: [[(0, 4), (4, 2), (6, 2), (8, 6), (14, 2)], [(0, 2), (2, 2), (4, 4), (8, 4), (12, 4)], [(0, 6), (6, 2), (8, 2), (10, 2), (12, 4)]],
                             leadBase: 7, pulse: 0.5, bassPulse: false, arpPattern: [0, 1, 2, 1, 0, 2, 1, 2], padOctave: 2, brightness: 0.45)
        case .waldbrand:
            return ThemeSpec(tonic: 40, scale: [0, 1, 3, 5, 7, 8, 10], bpm: 92,
                             progression: [0, 0, 1, 0, 0, 5, 1, 0], timbre: .brass,
                             rhythms: [[(0, 3), (3, 1), (4, 4), (10, 2), (12, 4)], [(0, 2), (2, 2), (4, 2), (8, 3), (11, 1), (12, 4)], [(0, 6), (8, 2), (10, 2), (12, 4)]],
                             leadBase: 14, pulse: 1, bassPulse: true, arpPattern: [0, 2, 1, 2], padOctave: 2, brightness: 0.5)
        case .kueste:
            return ThemeSpec(tonic: 42, scale: [0, 2, 3, 5, 7, 8, 10], bpm: 80,
                             progression: [0, 5, 3, 4, 0, 6, 5, 4], timbre: .flute,
                             rhythms: [[(0, 8), (8, 6)], [(0, 6), (6, 2), (8, 8)], [(2, 6), (8, 4), (12, 4)]],
                             leadBase: 7, pulse: 0.8, bassPulse: true, arpPattern: [0, 2, 1, 2, 0, 1, 2, 1], padOctave: 2, brightness: 0.3)
        case .altstadt:
            return ThemeSpec(tonic: 50, scale: [0, 2, 3, 5, 7, 8, 11], bpm: 100,
                             progression: [0, 3, 4, 0, 5, 3, 4, 0], timbre: .pluck,
                             rhythms: [[(0, 2), (3, 1), (4, 2), (7, 1), (8, 4), (12, 2)], [(0, 3), (3, 3), (6, 2), (8, 2), (12, 4)], [(0, 1), (2, 2), (4, 2), (8, 4), (13, 3)]],
                             leadBase: 7, pulse: 0.7, bassPulse: true, arpPattern: [0, 1, 2, 1], padOctave: 1, brightness: 0.5)
        case .vulkan:
            return ThemeSpec(tonic: 36, scale: [0, 1, 4, 5, 7, 8, 10], bpm: 66,
                             progression: [0, 1, 0, 5, 0, 1, 6, 0], timbre: .brass,
                             rhythms: [[(0, 8), (8, 4), (12, 4)], [(0, 4), (4, 4), (8, 8)], [(0, 3), (4, 3), (8, 3), (12, 4)]],
                             leadBase: 14, pulse: 1, bassPulse: false, arpPattern: [0, 2, 1, 2], padOctave: 2, brightness: 0.25)
        case .gebirge:
            return ThemeSpec(tonic: 51, scale: [0, 2, 4, 6, 7, 9, 11], bpm: 70,
                             progression: [0, 1, 4, 0, 0, 5, 1, 4], timbre: .bell,
                             rhythms: [[(0, 6), (8, 4), (12, 4)], [(0, 8), (8, 6)], [(0, 4), (6, 2), (8, 4), (14, 2)]],
                             leadBase: 7, pulse: 0.3, bassPulse: false, arpPattern: [0, 2, 1, 2, 0, 1], padOctave: 1, brightness: 0.55)
        case .bohrinsel:
            return ThemeSpec(tonic: 43, scale: [0, 2, 3, 5, 6, 8, 10], bpm: 88,
                             progression: [0, 0, 6, 5, 0, 3, 5, 6], timbre: .brass,
                             rhythms: [[(0, 4), (6, 2), (8, 4), (12, 4)], [(0, 2), (2, 2), (4, 6), (12, 4)], [(0, 6), (8, 3), (11, 5)]],
                             leadBase: 7, pulse: 0.9, bassPulse: true, arpPattern: [0, 1, 2, 2, 1, 0], padOctave: 2, brightness: 0.35)
        case .staudamm:
            return ThemeSpec(tonic: 47, scale: [0, 2, 3, 5, 7, 8, 11], bpm: 108,
                             progression: [0, 0, 5, 4, 0, 3, 4, 4], timbre: .pluck,
                             rhythms: [[(0, 2), (2, 2), (4, 4), (8, 2), (10, 2), (12, 4)], [(0, 3), (3, 3), (6, 4), (10, 6)], [(0, 4), (4, 2), (6, 2), (8, 8)]],
                             leadBase: 7, pulse: 1, bassPulse: true, arpPattern: [0, 1, 2, 1, 0, 1, 2, 2], padOctave: 1, brightness: 0.4)
        case .passhoehe:
            return ThemeSpec(tonic: 53, scale: [0, 2, 3, 5, 7, 8, 10], bpm: 64,
                             progression: [0, 5, 0, 3, 6, 5, 3, 4], timbre: .bell,
                             rhythms: [[(0, 8), (10, 6)], [(4, 4), (8, 8)], [(0, 6), (8, 4), (14, 2)]],
                             leadBase: 7, pulse: 0.4, bassPulse: false, arpPattern: [0, 2, 1, 2, 0, 1, 2, 1], padOctave: 2, brightness: 0.6)
        case .wueste:
            return ThemeSpec(tonic: 48, scale: [0, 1, 4, 5, 7, 8, 11], bpm: 84,
                             progression: [0, 0, 1, 0, 3, 1, 6, 0], timbre: .pluck,
                             rhythms: [[(0, 3), (3, 1), (4, 4), (8, 3), (11, 1), (12, 4)], [(0, 6), (6, 2), (8, 8)], [(0, 2), (4, 2), (6, 2), (8, 4), (12, 4)]],
                             leadBase: 7, pulse: 0.6, bassPulse: false, arpPattern: [0, 2, 1, 0, 2, 1], padOctave: 1, brightness: 0.45)
        case .win:
            return ThemeSpec(tonic: 50, scale: [0, 2, 4, 5, 7, 9, 11], bpm: 96, progression: [0, 3, 0], timbre: .bell,
                             rhythms: [], leadBase: 7, pulse: 0, bassPulse: false, arpPattern: [0, 1, 2], padOctave: 1, brightness: 0.55)
        case .lose:
            return ThemeSpec(tonic: 50, scale: [0, 2, 3, 5, 7, 8, 10], bpm: 66, progression: [0, 5, 0], timbre: .flute,
                             rhythms: [], leadBase: 7, pulse: 0, bassPulse: false, arpPattern: [0, 1, 2], padOctave: 1, brightness: 0.2)
        }
    }
}

/// Small deterministic random generator (SplitMix64): the same seed always gives the same music.
struct MusicRNG {
    var state: UInt64
    init(_ seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9e37_79b9_7f4a_7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58_476d_1ce4_e5b9
        z = (z ^ (z >> 27)) &* 0x94d0_49bb_1331_11eb
        return z ^ (z >> 31)
    }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(1, n))) }
}

/// The finished arrangement of one theme: notes per bar and step, independent of the intensity
/// (which layers sound is decided at playback by `minIntensity`).
public struct MusicScore: Sendable {
    public static let stepsPerBar = 16
    public let theme: MusicTheme
    public let seed: UInt64
    public let bars: Int
    public let bpm: Double
    public let timbre: LeadTimbre
    public let brightness: Float
    /// Notes starting at (bar * 16 + step).
    let table: [[MusicNote]]

    public var loops: Bool { theme.loops }
    public var allNotes: [MusicNote] { table.flatMap { $0 } }
    /// Notes for the lead voice with their scale, for tests.
    public var scaleClasses: Set<Int> {
        let s = theme.spec
        return Set(s.scale.map { (s.tonic + $0) % 12 })
    }

    @inline(__always) func notes(bar: Int, step: Int) -> [MusicNote] { table[bar * Self.stepsPerBar + step] }

    public init(theme: MusicTheme, seed: UInt64? = nil) {
        self.theme = theme
        let seed = seed ?? theme.defaultSeed
        self.seed = seed
        let spec = theme.spec
        bpm = spec.bpm
        timbre = spec.timbre
        brightness = spec.brightness
        var notes: [(bar: Int, note: MusicNote)] = []
        let bars: Int
        switch theme {
        case .win, .lose:
            bars = 3
            notes = Self.ending(theme, spec)
        default:
            bars = spec.progression.count
            notes = Self.arrangement(spec, seed: seed ^ theme.defaultSeed)
        }
        self.bars = bars
        var t = [[MusicNote]](repeating: [], count: bars * Self.stepsPerBar)
        for (bar, n) in notes where bar < bars && n.step < Self.stepsPerBar { t[bar * Self.stepsPerBar + n.step].append(n) }
        table = t
    }

    // MARK: Helpers

    /// MIDI note of scale index `i` (0 = tonic, 7 = tonic one octave up, negative allowed).
    static func pitch(_ s: ThemeSpec, _ i: Int) -> Int {
        let oct = Int((Double(i) / 7).rounded(.down))
        let idx = i - oct * 7
        return s.tonic + s.scale[idx] + 12 * oct
    }

    /// Scale indices of the chord on a degree: root, third, fifth.
    static func chord(_ degree: Int) -> [Int] { [degree, degree + 2, degree + 4] }

    // MARK: Arrangement of the looping themes

    private static func arrangement(_ s: ThemeSpec, seed: UInt64) -> [(bar: Int, note: MusicNote)] {
        var out: [(bar: Int, note: MusicNote)] = []
        var rng = MusicRNG(seed)
        let bars = s.progression.count

        // Four melody bars: A, B, C (half close), D (close on the tonic). The 8-bar form is A B A C | A B' A' D.
        func makeBar(_ chordDegree: Int, ending: Bool, close: Bool) -> [(Int, Int, Int)] {
            let tpl = s.rhythms[rng.int(s.rhythms.count)]
            let ch = chord(chordDegree)
            var idx = s.leadBase + ch[rng.int(3)] % 7
            var notes: [(Int, Int, Int)] = []
            for (k, (step, len)) in tpl.enumerated() {
                if k > 0 { idx += [-2, -1, -1, 0, 1, 1, 2][rng.int(7)] }
                idx = min(max(idx, s.leadBase - 2), s.leadBase + 8)
                if step % 4 == 0 || (ending && k == tpl.count - 1) {
                    // Strong beat: land on a chord tone.
                    idx = nearestChordTone(idx, chord: ch)
                }
                if close && k == tpl.count - 1 { idx = s.leadBase + (rng.int(2) == 0 ? 0 : 4) }
                notes.append((step, len, idx))
            }
            return notes
        }
        let motifA = makeBar(s.progression[0], ending: false, close: false)
        let motifB = makeBar(s.progression[1], ending: false, close: false)
        let motifC = makeBar(s.progression[2 % bars], ending: true, close: false)
        let motifD = makeBar(s.progression[0], ending: true, close: true)
        // Bars as (motif, shift in scale steps) – the varied repeat keeps the melody recognisable.
        let form: [([(Int, Int, Int)], Int)] = [
            (motifA, 0), (motifB, 0), (motifA, 0), (motifC, 0),
            (motifA, 0), (motifB, 2), (motifA, 1), (motifD, 0)
        ]

        for bar in 0..<bars {
            let degree = s.progression[bar]
            let ch = chord(degree)
            let root = pitch(s, degree)
            let fifth = pitch(s, degree + 4)
            let pulseGain = max(0.4, s.pulse)

            // Pad: the chord, one bar long, one octave or two up (padOctave scale indices of 7).
            for (k, ci) in ch.enumerated() {
                out.append((bar, MusicNote(step: 0, length: 17, midi: pitch(s, ci) + 12 * (s.padOctave - 1) + (k == 0 ? 12 : 0),
                                           velocity: 0.55, layer: .pad, minIntensity: 0)))
            }
            // A 7th-or-octave voice joins when it gets tense.
            out.append((bar, MusicNote(step: 0, length: 17, midi: pitch(s, degree + 6) + 12 * (s.padOctave - 1) + 12,
                                       velocity: 0.4, layer: .pad, minIntensity: 0.7)))

            // Bass
            let bassRoot = root >= 45 ? root - 12 : root
            out.append((bar, MusicNote(step: 0, length: 7, midi: bassRoot, velocity: 0.8, layer: .bass, minIntensity: 0.12)))
            var bassFifth = fifth
            while bassFifth - bassRoot > 9 { bassFifth -= 12 }
            while bassFifth < bassRoot { bassFifth += 12 }
            out.append((bar, MusicNote(step: 8, length: 5, midi: bar % 2 == 0 ? bassRoot : bassFifth,
                                       velocity: 0.7, layer: .bass, minIntensity: 0.3)))
            if s.bassPulse {
                for st in stride(from: 2, to: 16, by: 2) where st != 8 {
                    out.append((bar, MusicNote(step: st, length: 1, midi: bassRoot, velocity: 0.55, layer: .bass, minIntensity: 0.62)))
                }
            }

            // Arpeggio: eighths from 0.35, sixteenths between them from 0.65.
            for e in 0..<8 {
                let ci = ch[s.arpPattern[e % s.arpPattern.count] % 3]
                let m = pitch(s, ci + 7)
                out.append((bar, MusicNote(step: e * 2, length: 2, midi: m, velocity: 0.45, layer: .arp, minIntensity: 0.35)))
                out.append((bar, MusicNote(step: e * 2 + 1, length: 1, midi: m + 12, velocity: 0.3, layer: .arp, minIntensity: 0.68)))
            }

            // Percussion
            if s.pulse > 0 {
                out.append((bar, MusicNote(step: 0, length: 1, midi: 0, velocity: 0.8 * pulseGain, layer: .pulse, minIntensity: 0.55)))
                out.append((bar, MusicNote(step: 8, length: 1, midi: 0, velocity: 0.7 * pulseGain, layer: .pulse, minIntensity: 0.55)))
                for st in [2, 6, 10, 14] {
                    out.append((bar, MusicNote(step: st, length: 1, midi: 1, velocity: 0.5 * pulseGain, layer: .pulse, minIntensity: 0.7)))
                }
                for st in [4, 12] {
                    out.append((bar, MusicNote(step: st, length: 1, midi: 0, velocity: 0.55 * pulseGain, layer: .pulse, minIntensity: 0.85)))
                }
            }

            // Urgent high ticks: alternate root and fifth, very tight.
            for e in 0..<8 {
                let m = (e % 2 == 0 ? root : fifth) + 36
                out.append((bar, MusicNote(step: e * 2, length: 1, midi: m, velocity: 0.28, layer: .high, minIntensity: 0.82)))
            }

            // Lead: main notes at any intensity, short passing notes only when it is busier.
            let (motif, shift) = form[bar % form.count]
            for (step, len, idx) in motif {
                let ornament = len == 1 || (step % 2 == 1)
                let i = idx + (ornament ? 0 : shift)
                let ch2 = ch
                let snapped = ornament ? i : (step % 4 == 0 ? nearestChordTone(i, chord: ch2) : i)
                out.append((bar, MusicNote(step: step, length: min(len, 16 - step), midi: pitch(s, snapped),
                                           velocity: 0.7, layer: .lead, minIntensity: ornament ? 0.45 : 0)))
            }
            _ = rng.next()
        }
        return out
    }

    /// Scale index nearest to `idx` that belongs to the chord (in any octave).
    private static func nearestChordTone(_ idx: Int, chord ch: [Int]) -> Int {
        var best = idx, bestDist = Int.max
        for c in ch {
            let base = c % 7
            for oct in -2...3 {
                let cand = base + 7 * oct
                let d = abs(cand - idx)
                if d < bestDist || (d == bestDist && cand < best) { best = cand; bestDist = d }
            }
        }
        return best
    }

    // MARK: Endings

    private static func ending(_ theme: MusicTheme, _ s: ThemeSpec) -> [(bar: Int, note: MusicNote)] {
        var out: [(bar: Int, note: MusicNote)] = []
        func lead(_ bar: Int, _ step: Int, _ len: Int, _ idx: Int, _ v: Float = 0.75) {
            out.append((bar, MusicNote(step: step, length: len, midi: pitch(s, idx), velocity: v, layer: .lead, minIntensity: 0)))
        }
        func pad(_ bar: Int, degree: Int, len: Int) {
            for (k, ci) in chord(degree).enumerated() {
                out.append((bar, MusicNote(step: 0, length: len, midi: pitch(s, ci) + (k == 0 ? 12 : 0), velocity: 0.55, layer: .pad, minIntensity: 0)))
            }
            out.append((bar, MusicNote(step: 0, length: len, midi: pitch(s, degree) - 12, velocity: 0.7, layer: .bass, minIntensity: 0)))
        }
        if theme == .win {
            // Rising line, then a settled chord with a high bell on top.
            lead(0, 0, 2, 7); lead(0, 2, 2, 9); lead(0, 4, 2, 11); lead(0, 6, 8, 14)
            lead(1, 0, 2, 13); lead(1, 2, 2, 11); lead(1, 4, 2, 9); lead(1, 6, 10, 11)
            lead(2, 0, 16, 14, 0.6); lead(2, 4, 12, 18, 0.4)
            pad(0, degree: 0, len: 16); pad(1, degree: 3, len: 16); pad(2, degree: 0, len: 16)
            out.append((2, MusicNote(step: 0, length: 16, midi: pitch(s, 7) + 12, velocity: 0.4, layer: .pad, minIntensity: 0)))
        } else {
            // Falling line over a darkening chord, ending low and quiet.
            lead(0, 0, 4, 11, 0.7); lead(0, 4, 4, 9); lead(0, 8, 6, 8)
            lead(1, 0, 6, 7); lead(1, 6, 2, 6); lead(1, 8, 8, 4, 0.6)
            lead(2, 0, 16, 0, 0.5)
            pad(0, degree: 0, len: 16); pad(1, degree: 5, len: 16); pad(2, degree: 0, len: 16)
        }
        return out
    }
}
