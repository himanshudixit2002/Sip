import Foundation

/// A day's hydration score out of 100, in four parts that each reward a
/// different habit, so a high score means more than one big glass at night.
public struct HydrationScore: Equatable, Sendable {
    /// 0–50: how much of the goal was reached.
    public var amount: Int
    /// 0–20: how evenly drinks were spread through the waking day.
    public var spread: Int
    /// 0–10: staying well under the caffeine limit.
    public var caffeine: Int
    /// 0–20: goals met on the seven days before.
    public var consistency: Int

    public var total: Int { amount + spread + caffeine + consistency }
    public var grade: String { HydrationScore.grade(for: total) }

    public init(amount: Int, spread: Int, caffeine: Int, consistency: Int) {
        self.amount = amount
        self.spread = spread
        self.caffeine = caffeine
        self.consistency = consistency
    }

    /// One word for a score: Excellent, Great, Good, Fair or Low.
    public static func grade(for total: Int) -> String {
        switch total {
        case 90...: return "Excellent"
        case 75...: return "Great"
        case 60...: return "Good"
        case 40...: return "Fair"
        default: return "Low"
        }
    }
}

public enum Score {
    public static let amountPoints = 50
    public static let spreadPoints = 20
    public static let caffeinePoints = 10
    public static let consistencyPoints = 20
    public static let spreadBlocks = 4
    /// Share of the goal a block needs to count as covered.
    public static let blockShare = 0.10

    /// The score for `day`.
    ///
    /// - Parameters:
    ///   - entries: the day's entries.
    ///   - caffeineLimitMG: the daily limit, or nil when caffeine tracking is
    ///     off (which earns the full 10).
    ///   - summaries: used for the seven days before `day`.
    public static func daily(entries: [Entry], day: DayKey, goal: Double, hours: ActiveHours, clock: DayClock,
                             factors: HydrationFactors, rates: CaffeineRates, caffeineLimitMG: Double?,
                             summaries: [DayKey: DaySummary]) -> HydrationScore {
        let effective = entries.reduce(0) { $0 + $1.effectiveML(factors) }

        // Amount: the full 50 only once the goal is actually met.
        var amount = 0
        if goal > 0 {
            let ratio = effective >= goal - 0.5 ? 1 : min(max(effective / goal, 0), 1)
            amount = Int((ratio * Double(amountPoints)).rounded(.down))
        }

        // Spread: four equal blocks of the waking day, 5 points for each that
        // got at least 10% of the goal. Drinks before waking count toward the
        // first block and after bedtime toward the last.
        var spread = 0
        if goal > 0 {
            let window = hours.window(on: day, clock: clock)
            let length = window.sleep.timeIntervalSince(window.wake) / Double(spreadBlocks)
            var blocks = [Double](repeating: 0, count: spreadBlocks)
            for entry in entries {
                let offset = entry.date.timeIntervalSince(window.wake)
                let index = length > 0 ? min(max(Int((offset / length).rounded(.down)), 0), spreadBlocks - 1) : 0
                blocks[index] += entry.effectiveML(factors)
            }
            let perBlock = spreadPoints / spreadBlocks
            spread = blocks.filter { $0 >= goal * blockShare - 0.5 }.count * perBlock
        }

        // Caffeine: full marks up to half the limit, then down to 0 at the limit.
        var caffeine = caffeinePoints
        if let limit = caffeineLimitMG, limit > 0 {
            let mg = rates.milligrams(in: entries)
            if mg >= limit {
                caffeine = 0
            } else if mg > limit / 2 {
                caffeine = Int((Double(caffeinePoints) * (limit - mg) / (limit / 2)).rounded())
            }
        }

        // Consistency: met days among the seven before.
        let met = (1...7).filter { summaries[day.adding(days: -$0)]?.met == true }.count
        let consistency = Int((Double(met) * Double(consistencyPoints) / 7).rounded())

        return HydrationScore(amount: amount, spread: spread, caffeine: caffeine, consistency: consistency)
    }
}
