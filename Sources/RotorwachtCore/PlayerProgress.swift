import Foundation

public struct MissionRecord: Codable, Equatable, Sendable {
    public var stars: Int
    public var score: Int
}

/// What the player has achieved so far. Stored locally as JSON; pure logic here, the app decides where the file lives.
public struct PlayerProgress: Codable, Equatable, Sendable {
    /// Key: "<mission id>|<difficulty>".
    public private(set) var records: [String: MissionRecord] = [:]
    public init() {}

    private static func key(_ id: String, _ level: Difficulty) -> String { "\(id)|\(level.rawValue)" }

    public func best(_ id: String, _ level: Difficulty) -> MissionRecord? { records[Self.key(id, level)] }

    /// Keeps the better stars and score per mission and level.
    public mutating func record(missionID id: String, level: Difficulty, result: MissionResult) {
        let k = Self.key(id, level)
        let old = records[k]
        records[k] = MissionRecord(stars: max(old?.stars ?? 0, result.stars), score: max(old?.score ?? 0, result.score))
    }

    /// An Einsatz counts as accomplished with at least one star on any level.
    public func isCleared(_ id: String) -> Bool {
        Difficulty.allCases.contains { (best(id, $0)?.stars ?? 0) >= 1 }
    }

    /// The first Einsatz is always open, every further one once its predecessor is cleared.
    public func isUnlocked(_ id: String, order: [String]) -> Bool {
        guard let i = order.firstIndex(of: id) else { return false }
        return i == 0 || isCleared(order[i - 1])
    }

    // MARK: Storage

    public static func load(from url: URL) -> PlayerProgress {
        guard let data = try? Data(contentsOf: url), let p = try? JSONDecoder().decode(PlayerProgress.self, from: data) else { return PlayerProgress() }
        return p
    }

    public func save(to url: URL) {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: url, options: .atomic) }
    }
}
