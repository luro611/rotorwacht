import Foundation

// Score: 100 per rescued person as before, plus three bonuses (Planung 06, Teil 0.7b). Stars do not depend on any of it.
//
//  - time bonus   per rescued person, up to `timeBonusMax`, in proportion to the time still left
//  - combo bonus  per rescued person `comboStep` per earlier person of the chain (chain = rescues in a row
//                 without damage to the helicopter and without anybody lost), at most `comboCap` steps
//  - flight bonus a flight that lands at the camp with a full cabin, or with everybody of the Einsatz at once
//
// At the end: minus 50 per helicopter lost, plus the seconds left when everybody is resolved (as before).

public enum Scoring {
    public static let perPerson = 100
    public static let perHelicopterLost = 50
    public static let timeBonusMax = 40
    public static let comboStep = 5
    public static let comboCap = 10
    public static let fullCabinBonus = 50
    public static let allInOneFlightBonus = 300
    /// A broken chain is only announced from this length on.
    public static let announceBreakFrom = 3
}

/// Bonus points and the running chain of rescues of one Einsatz.
public struct ScoreTally: Equatable, Sendable {
    public var timeBonus = 0
    public var comboBonus = 0
    public var flightBonus = 0
    /// Rescues in a row without damage or loss.
    public var combo = 0
    public var bestCombo = 0
}

extension MissionSimulation {
    /// Points as shown during the flight: what the result will show, without the end-of-Einsatz seconds.
    public var livePoints: Int {
        max(0, rescuedCount * Scoring.perPerson - (mission.helicopters - helicoptersLeft) * Scoring.perHelicopterLost
            + tally.timeBonus + tally.comboBonus + tally.flightBonus)
    }

    mutating func awardRescue(_ events: inout [SimEvent]) {
        let share = mission.timeLimit > 0 ? timeLeft / mission.timeLimit : 0
        let time = Int((Double(Scoring.timeBonusMax) * share).rounded())
        tally.combo += 1
        tally.bestCombo = max(tally.bestCombo, tally.combo)
        let combo = min(tally.combo - 1, Scoring.comboCap) * Scoring.comboStep
        tally.timeBonus += time
        tally.comboBonus += combo
        events.append(.scored(points: Scoring.perPerson + time + combo, combo: tally.combo))
    }

    mutating func breakCombo(_ events: inout [SimEvent]) {
        guard tally.combo > 0 else { return }
        if tally.combo >= Scoring.announceBreakFrom { events.append(.comboBroken(was: tally.combo)) }
        tally.combo = 0
    }

    /// Called when the first person of a delivery steps out at the camp; `delivered` = people aboard on arrival.
    mutating func awardFlight(delivered: Int, _ events: inout [SimEvent]) {
        guard !flightPaid else { return }
        flightPaid = true
        let everybody = people.count >= 2 && delivered == people.count
        let full = delivered >= mission.capacity
        let points = everybody ? Scoring.allInOneFlightBonus : (full ? Scoring.fullCabinBonus : 0)
        guard points > 0 else { return }
        tally.flightBonus += points
        events.append(.flightBonus(points: points, people: delivered, all: everybody))
    }
}
