import Foundation

public struct ScoreEntry: Codable, Equatable, Sendable {
    public var name: String
    public var score: Int
    public var stars: Int
    public var date: Date
    public init(name: String, score: Int, stars: Int, date: Date) {
        self.name = name; self.score = score; self.stars = stars; self.date = date
    }
}

/// The best results per Einsatz and level (top 10). Stored locally as JSON; pure logic here, the app decides where the file lives.
public struct HighScores: Codable, Equatable, Sendable {
    public static let limit = 10
    public static let maxNameLength = 16
    public static let defaultName = "Pilot"

    /// Key: "<mission id>|<difficulty>".
    public private(set) var lists: [String: [ScoreEntry]] = [:]
    public init() {}

    private static func key(_ id: String, _ level: Difficulty) -> String { "\(id)|\(level.rawValue)" }

    /// A name as it is stored: trimmed, without line breaks, at most 16 characters; empty becomes "Pilot".
    public static func cleanName(_ raw: String) -> String {
        let flat = raw.components(separatedBy: .newlines).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        let cut = String(flat.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        return cut.isEmpty ? defaultName : cut
    }

    /// Best first: more points, then more stars, then the earlier one.
    private static func ranks(before a: ScoreEntry, _ b: ScoreEntry) -> Bool {
        if a.score != b.score { return a.score > b.score }
        if a.stars != b.stars { return a.stars > b.stars }
        return a.date < b.date
    }

    public func list(_ id: String, _ level: Difficulty) -> [ScoreEntry] { lists[Self.key(id, level)] ?? [] }

    /// Place (0 = best) a result would take, nil when it does not make the list. Zero points never qualify.
    public func place(forScore score: Int, stars: Int, mission id: String, level: Difficulty) -> Int? {
        guard score > 0 else { return nil }
        let entry = ScoreEntry(name: "", score: score, stars: stars, date: .distantFuture)
        let l = list(id, level)
        let i = l.firstIndex { Self.ranks(before: entry, $0) } ?? l.count
        return i < Self.limit ? i : nil
    }

    /// Adds a result and returns its place (0 = best), nil when it did not make the list.
    @discardableResult
    public mutating func add(_ entry: ScoreEntry, mission id: String, level: Difficulty) -> Int? {
        guard place(forScore: entry.score, stars: entry.stars, mission: id, level: level) != nil else { return nil }
        var e = entry
        e.name = Self.cleanName(entry.name)
        var l = list(id, level)
        l.append(e)
        l.sort(by: Self.ranks(before:_:))   // stable enough: equal entries differ in date
        let place = l.firstIndex(of: e)
        lists[Self.key(id, level)] = Array(l.prefix(Self.limit))
        return place
    }

    // MARK: Storage

    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }

    public static func load(from url: URL) -> HighScores {
        guard let data = try? Data(contentsOf: url), let s = try? decoder.decode(HighScores.self, from: data) else { return HighScores() }
        return s
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
