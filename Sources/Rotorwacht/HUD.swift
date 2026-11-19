import Foundation

struct MiniMapPoint: Equatable {
    var x: Double
    var waiting: Int
    var endangered: Bool
}

/// What the on-screen display shows; the scene fills it a few times per second.
struct HUDSnapshot: Equatable {
    var fuel = 1.0
    var durability = 1.0
    var aboard = 0
    var capacity = 12
    var rescued = 0
    var total = 0
    var lost = 0
    var timeLeft = 0.0
    var helicoptersLeft = 3
    var helicoptersTotal = 3
    var wind = 0.0
    var floodLevel = 0.0
    var heliX = 0.0
    var worldWidth = 1.0
    var baseX = 0.0
    var points: [MiniMapPoint] = []
    var messages: [String] = []
    var crashed = false
}
