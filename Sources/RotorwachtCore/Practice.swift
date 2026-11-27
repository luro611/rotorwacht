import Foundation

/// Practice mode: a short course per hazard, built from the existing Einsatz files. No score, no list entry,
/// no progress; unlimited helicopters, after a loss the next one stands at the start of the course at once.
public struct PracticeCourse: Equatable, Sendable {
    public var id: String
    public var title: String
    public var hint: String
    /// Einsatz file the course is built from.
    public var missionID: String
    /// Where the helicopter starts and restarts (world x).
    public var startX: Double
}

public enum Practice {
    public static let courses: [PracticeCourse] = [
        PracticeCourse(id: "unterfuehrung", title: "Unterführung", hint: "Unter der Brücke hindurch, Decke nicht berühren.", missionID: "altstadt", startX: 6350),
        PracticeCourse(id: "tunnel", title: "Tunnel mit Shuttern", hint: "Gelb warnt, Rot ist zu. Im Tor steckenbleiben verliert den Hubschrauber.", missionID: "vulkan", startX: 6900),
        PracticeCourse(id: "galerie", title: "Lawinengalerie", hint: "Shutter im Wind, dazu Lawinen vor dem Tunnel.", missionID: "gebirge", startX: 6800),
        PracticeCourse(id: "bruecke", title: "Brücke über der Flut", hint: "Die Flut verengt die Öffnung unter der Brücke.", missionID: "hochwasser", startX: 4300),
        PracticeCourse(id: "blitze", title: "Blitze", hint: "Roter Strahl, dann zur Seite fliegen.", missionID: "kueste", startX: 3000),
        PracticeCourse(id: "salven", title: "Trümmer und Nachbeben", hint: "Trümmer fallen, Plätze werden gesperrt.", missionID: "altstadt", startX: 2300),
        PracticeCourse(id: "lava", title: "Lava und Lavabrocken", hint: "Gestrichelte Bahnen zeigen die Brocken.", missionID: "vulkan", startX: 4400),
        PracticeCourse(id: "lawine", title: "Lawinen und Seilwinde", hint: "Schwebe ruhig über dem Vorsprung, das Seil zieht hoch.", missionID: "gebirge", startX: 3700),
        PracticeCourse(id: "flutwelle", title: "Flutwelle und Brücken", hint: "Unter den Brücken hindurch, die Welle kommt von hinten.", missionID: "staudamm", startX: 2800),
        PracticeCourse(id: "eis", title: "Vereisung", hint: "Eis macht träge, an der Straßenmeisterei taut es ab.", missionID: "pass", startX: 3300),
        PracticeCourse(id: "deck", title: "Schwankende Decks", hint: "Sanft aufsetzen, der Hubschrauber fährt mit der Fläche.", missionID: "bohrinsel", startX: 6500),
        PracticeCourse(id: "feuer", title: "Löschen", hint: "Tank über dem See füllen, Leertaste wirft Wasser ab.", missionID: "waldbrand", startX: 600),
    ]

    public static func course(_ id: String) -> PracticeCourse? { courses.first { $0.id == id } }
}

extension Mission {
    public var isPractice: Bool { practice ?? false }

    /// Gentler hazards: longer open and warning times, fewer and slower strikes, flood and lava slower.
    public func slowed() -> Mission {
        var m = self
        m.flood.risePerSecond *= 0.5
        m.storms = m.storms?.map { var s = $0; s.interval *= 1.5; s.warn *= 1.6; s.damage *= 0.7; return s }
        m.volleys = m.volleys?.map { var v = $0; v.interval *= 1.5; v.warn *= 1.6; v.damage *= 0.7; return v }
        m.flows = m.flows?.map { var f = $0; f.speed *= 0.6; f.warn *= 1.6; f.damagePerSecond *= 0.7; return f }
        m.passages = m.passages?.map { p in
            var q = p
            q.shutters = p.shutters?.map { s in
                var t = s
                let closed = s.period - s.open
                t.open = s.open * 1.5
                t.period = t.open + closed
                t.warn = s.warn * 1.6
                return t
            }
            return q
        }
        return m
    }

    /// The Einsatz as a practice course on a level: no time limit, no fuel burn, restart at the course start.
    public func practiced(course: PracticeCourse, level: Difficulty, slow: Bool) -> Mission {
        var m = scaled(for: level)
        if slow { m = m.slowed() }
        m.practice = true
        m.startX = course.startX
        m.timeLimit = 100_000
        m.fuel.burnPerSecond = 0
        m.helicopters = 1
        return m
    }
}
