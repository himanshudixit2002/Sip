import Foundation

public struct StreakResult: Equatable, Sendable, CustomStringConvertible {
    /// Consecutive days the goal was met, counting today only once it's met.
    public var current: Int
    public var best: Int
    /// Freezes in the bank right now.
    public var freezesBanked: Int
    /// Missed days that a freeze covered.
    public var frozenDays: Set<DayKey>
    public var todayMet: Bool

    public static let zero = StreakResult(current: 0, best: 0, freezesBanked: 0, frozenDays: [], todayMet: false)

    public var nextMilestone: Int? { Streaks.milestones.first { $0 > current } }

    /// The highest milestone reached, if any.
    public var milestone: Int? { Streaks.milestones.last { $0 <= current } }

    /// "6-day streak", or "No streak yet" before the first met day.
    public var description: String { current > 0 ? "\(current)-day streak" : "No streak yet" }
}

public enum Streaks {
    public static let milestones = [3, 7, 14, 30, 50, 100, 365]
    /// A freeze is earned each time the streak reaches a multiple of this.
    public static let freezeEvery = 7
    public static let maxFreezes = 2

    /// Recomputed from the full history every time, so there is no streak state
    /// to drift out of step with the entries.
    ///
    /// - Parameters:
    ///   - metDays: every day on which the goal was met.
    ///   - firstDay: the earliest day with any entry.
    ///   - today: the current drinking day. An unmet today never breaks the
    ///     streak — the day isn't over.
    ///   - repairs: missed days won back by a comeback (see `Comeback`). They
    ///     count exactly like met days.
    public static func compute(
        metDays: Set<DayKey>,
        firstDay: DayKey?,
        today: DayKey,
        freezesEnabled: Bool,
        repairs: Set<DayKey> = []
    ) -> StreakResult {
        let metDays = repairs.isEmpty ? metDays : metDays.union(repairs)
        let todayMet = metDays.contains(today)
        guard let firstDay, firstDay < today else {
            let count = todayMet ? 1 : 0
            return StreakResult(current: count, best: count, freezesBanked: 0, frozenDays: [], todayMet: todayMet)
        }

        var run = 0
        var best = 0
        var bank = 0
        var frozen: Set<DayKey> = []

        var day = firstDay
        while day < today {
            if metDays.contains(day) {
                run += 1
                best = max(best, run)
                if freezesEnabled, run % freezeEvery == 0 {
                    bank = min(bank + 1, maxFreezes)
                }
            } else if freezesEnabled, run > 0, bank > 0 {
                // The streak survives the miss but doesn't grow.
                bank -= 1
                frozen.insert(day)
            } else {
                run = 0
            }
            day = day.next
        }

        var current = run
        if todayMet {
            current += 1
            if freezesEnabled, current % freezeEvery == 0 {
                bank = min(bank + 1, maxFreezes)
            }
        }
        best = max(best, current)
        return StreakResult(current: current, best: best, freezesBanked: bank, frozenDays: frozen, todayMet: todayMet)
    }
}
