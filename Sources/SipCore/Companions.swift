import Foundation

/// How the desk plant looks, all derived from recent days.
public struct PlantState: Equatable, Sendable {
    /// 0–8, one more for roughly every two met days in the last fortnight.
    public var leaves: Int
    /// Flowers once the streak reaches a week.
    public var flowering: Bool
    /// 0–1: how far the leaves hang. Only when behind pace today.
    public var droop: Double

    public init(leaves: Int, flowering: Bool, droop: Double) {
        self.leaves = leaves
        self.flowering = flowering
        self.droop = droop
    }
}

/// Little living things in the bottle and on the desk that grow with good
/// habits. They never die: the worst a plant does is droop until you drink.
public enum Companions {
    public static let maxLeaves = 8
    public static let floweringStreak = 7
    public static let behindPaceDroop = 0.6

    /// Fish in the bottle: 1, then 2 at a 7-day streak, 3 at 30 and 4 at 100.
    public static func fishCount(streak: Int) -> Int {
        switch streak {
        case 100...: return 4
        case 30...: return 3
        case 7...: return 2
        default: return 1
        }
    }

    /// `metLast14` is how many of the last 14 days met the goal. Leaves scale
    /// 14 met days to the full 8, rounding so the first met day already shows.
    public static func plant(metLast14: Int, streak: Int, behindPace: Bool) -> PlantState {
        let met = min(max(metLast14, 0), 14)
        let leaves = min((met * maxLeaves + 7) / 14, maxLeaves)
        return PlantState(leaves: leaves, flowering: streak >= floweringStreak, droop: behindPace ? behindPaceDroop : 0)
    }
}
