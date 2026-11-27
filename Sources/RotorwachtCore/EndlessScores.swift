import Foundation

public struct EndlessEntry: Codable, Equatable, Sendable {
    public var name: String
    /// Stages cleared.
    public var stages: Int
    public var score: Int
    public var date: Date
    public init(name: String, stages: Int, score: Int, date: Date) {
        self.name = name; self.stages = stages; self.score = score; self.date = date
    }
}

/// The best endless runs per level (top 10): more stages first, then more points, then the earlier one. Stored locally as JSON.
/// The medium list is `entries` (the only list older files have); the other levels are kept in `others`.
public struct EndlessScores: Codable, Equatable, Sendable {
    public static let limit = 10
    public private(set) var entries: [EndlessEntry] = []
    /// Lists of the other levels, keyed by the raw value of the level. Missing in files of older versions.
    private var others: [String: [EndlessEntry]]? = nil
    public init() {}

    public func list(_ level: Difficulty) -> [EndlessEntry] { level == .medium ? entries : others?[level.rawValue] ?? [] }

    private mutating func set(_ l: [EndlessEntry], _ level: Difficulty) {
        if level == .medium { entries = l } else { var o = others ?? [:]; o[level.rawValue] = l; others = o }
    }

    private static func ranks(before a: EndlessEntry, _ b: EndlessEntry) -> Bool {
        if a.stages != b.stages { return a.stages > b.stages }
        if a.score != b.score { return a.score > b.score }
        return a.date < b.date
    }

    /// Place (0 = best) a run would take, nil when it does not make the list. Runs without points never qualify.
    public func place(stages: Int, score: Int, level: Difficulty = .medium) -> Int? {
        guard score > 0 else { return nil }
        let e = EndlessEntry(name: "", stages: stages, score: score, date: .distantFuture)
        let l = list(level)
        let i = l.firstIndex { Self.ranks(before: e, $0) } ?? l.count
        return i < Self.limit ? i : nil
    }

    @discardableResult
    public mutating func add(_ entry: EndlessEntry, level: Difficulty = .medium) -> Int? {
        guard place(stages: entry.stages, score: entry.score, level: level) != nil else { return nil }
        var e = entry
        e.name = HighScores.cleanName(entry.name)
        var l = list(level)
        l.append(e)
        l.sort(by: Self.ranks(before:_:))
        let place = l.firstIndex(of: e)
        set(Array(l.prefix(Self.limit)), level)
        return place
    }

    @discardableResult
    public mutating func rename(place: Int, date: Date, to name: String, level: Difficulty = .medium) -> Bool {
        var l = list(level)
        guard l.indices.contains(place), l[place].date == date else { return false }
        l[place].name = HighScores.cleanName(name)
        set(l, level)
        return true
    }

    private static var decoder: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
    private static var encoder: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; e.outputFormatting = [.sortedKeys]; return e }

    public static func load(from url: URL) -> EndlessScores {
        guard let data = try? Data(contentsOf: url), let s = try? decoder.decode(EndlessScores.self, from: data) else { return EndlessScores() }
        return s
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? Self.encoder.encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
