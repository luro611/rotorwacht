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

/// The best endless runs (top 10): more stages first, then more points, then the earlier one. Stored locally as JSON.
public struct EndlessScores: Codable, Equatable, Sendable {
    public static let limit = 10
    public private(set) var entries: [EndlessEntry] = []
    public init() {}

    private static func ranks(before a: EndlessEntry, _ b: EndlessEntry) -> Bool {
        if a.stages != b.stages { return a.stages > b.stages }
        if a.score != b.score { return a.score > b.score }
        return a.date < b.date
    }

    /// Place (0 = best) a run would take, nil when it does not make the list. Runs without points never qualify.
    public func place(stages: Int, score: Int) -> Int? {
        guard score > 0 else { return nil }
        let e = EndlessEntry(name: "", stages: stages, score: score, date: .distantFuture)
        let i = entries.firstIndex { Self.ranks(before: e, $0) } ?? entries.count
        return i < Self.limit ? i : nil
    }

    @discardableResult
    public mutating func add(_ entry: EndlessEntry) -> Int? {
        guard place(stages: entry.stages, score: entry.score) != nil else { return nil }
        var e = entry
        e.name = HighScores.cleanName(entry.name)
        var l = entries
        l.append(e)
        l.sort(by: Self.ranks(before:_:))
        let place = l.firstIndex(of: e)
        entries = Array(l.prefix(Self.limit))
        return place
    }

    @discardableResult
    public mutating func rename(place: Int, date: Date, to name: String) -> Bool {
        guard entries.indices.contains(place), entries[place].date == date else { return false }
        entries[place].name = HighScores.cleanName(name)
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
