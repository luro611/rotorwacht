import Foundation

struct MiniMapPoint: Equatable {
    var x: Double
    var waiting: Int
    var endangered: Bool
}

struct MiniMapSpan: Equatable {
    var lo: Double
    var hi: Double
    var lava: Bool
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
    var water = 0.0
    var smoke = 0.0
    var heat = 0.0
    /// Ice on the helicopter and heat of the day, 0...1; -1 where the Einsatz has none.
    var ice = -1.0
    var swelter = -1.0
    var filling = false
    var points: [MiniMapPoint] = []
    /// x positions of burning stretches, for the overview bar.
    var fires: [Double] = []
    /// Stretches covered by lava or an avalanche.
    var spans: [MiniMapSpan] = []
    var outposts: [Double] = []
    /// Winch progress 0...1, -1 when no cable is in use.
    var winch = -1.0
    var winchSteady = true
    var messages: [String] = []
    var crashed = false
    /// Points so far and the current chain of rescues without damage.
    var score = 0
    var combo = 0
}
