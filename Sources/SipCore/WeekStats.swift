import Foundation

/// A run of days ending with `last`, the one place week maths lives. The
/// notification, the share card and the Insights week row all read from it.
public struct WeekStats: Equatable, Sendable {
    /// Oldest first, one per day. A day with nothing logged appears as an
    /// empty summary so charts keep their gaps.
    public var days: [DaySummary]
    /// Everything poured, before hydration factors.
    public var totalML: Double
    /// Mean effective intake per day across all `days`, empty days included:
    /// a skipped day really did bring the week's average down.
    public var averageML: Double
    public var metCount: Int
    /// The day with the most effective intake, or nil if nothing was logged.
    public var bestDay: DaySummary?

    /// - Parameters:
    ///   - count: how many days, ending with `last` (at least 1).
    ///   - fallbackGoal: the goal shown for days with no summary.
    public init(summaries: [DayKey: DaySummary], last: DayKey, count: Int = 7, fallbackGoal: Double = 0) {
        let n = max(count, 1)
        days = (0..<n).reversed().map { offset in
            let key = last.adding(days: -offset)
            return summaries[key] ?? .empty(key, goal: fallbackGoal)
        }
        totalML = days.reduce(0) { $0 + $1.rawML }
        averageML = days.reduce(0) { $0 + $1.effectiveML } / Double(n)
        metCount = days.filter(\.met).count
        // Ties go to the earlier day, so the answer doesn't depend on order.
        bestDay = days.filter { $0.effectiveML > 0 }.reduce(nil) { best, day in
            guard let best else { return day }
            return day.effectiveML > best.effectiveML ? day : best
        }
    }
}
