import Foundation

/// XP earned on one drinking day, split into its parts so the app can show
/// where the points came from.
public struct DayXP: Equatable, Sendable {
    /// 1 per 10 ml effective, up to 150% of the day's goal.
    public var intake: Int
    /// For meeting the goal.
    public var goal: Int
    /// Grows with each day of the current run of met days.
    public var streak: Int
    /// The daily challenge's reward, when it was completed.
    public var challenge: Int
    /// For a quarter of the goal before noon.
    public var early: Int

    public var total: Int { intake + goal + streak + challenge + early }

    public static let zero = DayXP(intake: 0, goal: 0, streak: 0, challenge: 0, early: 0)

    public init(intake: Int, goal: Int, streak: Int, challenge: Int, early: Int) {
        self.intake = intake
        self.goal = goal
        self.streak = streak
        self.challenge = challenge
        self.early = early
    }
}

/// Where a total XP sits on the 30-level ladder.
public struct LevelInfo: Equatable, Sendable {
    public var level: Int
    public var title: String
    public var xp: Int
    /// Total XP at which `level` began.
    public var levelStartXP: Int
    /// Total XP needed for the next level; equal to `levelStartXP` at the top.
    public var nextLevelXP: Int

    public var isMaxLevel: Bool { level >= XP.maxLevel }

    /// How far through the current level, 0–1. Always 1 at the top level.
    public var progress: Double {
        guard nextLevelXP > levelStartXP else { return 1 }
        return min(max(Double(xp - levelStartXP) / Double(nextLevelXP - levelStartXP), 0), 1)
    }

    public var xpToNextLevel: Int { max(nextLevelXP - xp, 0) }
}

/// Experience points, always recomputed from history and never stored, so an
/// edited or deleted entry can't leave a stale score behind.
///
/// Someone drinking about 2.5 L a day who meets their goal most days earns
/// roughly 350 XP a day, which reaches level 10 in about two months and the
/// top level in about a year and a half.
public enum XP {
    public static let mlPerPoint = 10.0
    /// Intake beyond this share of the goal earns nothing, so chugging extra
    /// water is never the best way to level up.
    public static let intakeCap = 1.5
    public static let goalBonus = 50
    public static let streakBonusPerDay = 2
    public static let streakBonusCapDays = 30
    public static let earlyBonus = 15
    /// Share of the goal to have by `earlyHour` for the early bonus.
    public static let earlyShare = 0.25
    public static let earlyHour = 12

    public static let titles = [
        "Droplet", "Dewdrop", "Raindrop", "Puddle", "Trickle", "Spring", "Brook", "Creek", "Stream", "Pond",
        "Rapids", "Waterfall", "River", "Lagoon", "Lake", "Delta", "Bay", "Fjord", "Sound", "Gulf",
        "Sea", "Glacier", "Reef", "Current", "Tide", "Monsoon", "Ocean", "Deep Ocean", "Abyss", "Poseidon",
    ]
    public static var maxLevel: Int { titles.count }

    /// XP for one day.
    ///
    /// - Parameters:
    ///   - streakDayIndex: the day's position in its run of met days, 1-based.
    ///     Ignored when the day wasn't met.
    ///   - challengeXP: the challenge's reward if it was completed, else 0.
    ///   - effectiveByNoon: effective intake logged before 12:00.
    public static func forDay(_ summary: DaySummary, streakDayIndex: Int, challengeXP: Int = 0,
                              effectiveByNoon: Double) -> DayXP {
        let goal = summary.goalML
        let counted = goal > 0 ? min(summary.effectiveML, goal * intakeCap) : summary.effectiveML
        // The tiny nudge stops 0.9 × 250 = 224.99999 from losing a point.
        let intake = Int((max(counted, 0) / mlPerPoint + 1e-9).rounded(.down))
        let met = summary.met
        let streak = met ? streakBonusPerDay * min(max(streakDayIndex, 0), streakBonusCapDays) : 0
        let early = goal > 0 && effectiveByNoon >= goal * earlyShare - 0.5 ? earlyBonus : 0
        return DayXP(intake: intake, goal: met ? goalBonus : 0, streak: streak,
                     challenge: max(challengeXP, 0), early: early)
    }

    /// XP for every logged day up to and including `today` (taken as it is so
    /// far). Groups entries by day once, so it stays fast over years of data.
    ///
    /// Each day's challenge is worked out again from current settings, so
    /// changing wake or sleep time can shift past challenges slightly.
    ///
    /// - Parameter repairs: comeback days (`Comeback.repairs`). They don't earn
    ///   the goal bonus, but they keep the run going for the streak bonus.
    public static func days(history: HydrationHistory, summaries: [DayKey: DaySummary], clock: DayClock,
                            factors: HydrationFactors, wakeMinutes: Int, sleepMinutes: Int = 23 * 60,
                            today: DayKey, repairs: Set<DayKey> = []) -> [DayKey: DayXP] {
        guard let first = summaries.keys.min() else { return [:] }
        let last = summaries.keys.max() ?? today
        let byDay = HistoryMath.entriesByDay(history.entries, clock: clock)
        var result: [DayKey: DayXP] = [:]
        var run = 0
        var day = first
        while day <= last {
            let summary = summaries[day]
            if summary?.met == true || repairs.contains(day) { run += 1 } else { run = 0 }
            if let summary, summary.entryCount > 0 {
                let entries = byDay[day] ?? []
                let noon = clock.time(earlyHour * 60, on: day)
                let byNoon = entries.reduce(0) { $1.date < noon ? $0 + $1.effectiveML(factors) : $0 }
                let yesterday = summaries[day.previous]?.effectiveML ?? 0
                let challenge = Challenges.challenge(for: day, goal: summary.goalML, wakeMinutes: wakeMinutes,
                                                     sleepMinutes: sleepMinutes, yesterdayML: yesterday)
                let progress = Challenges.progress(challenge, entries: entries, day: day, clock: clock,
                                                   goal: summary.goalML, yesterdayML: yesterday, factors: factors,
                                                   wakeMinutes: wakeMinutes, now: clock.end(of: day))
                result[day] = forDay(summary, streakDayIndex: summary.met ? run : 0,
                                     challengeXP: progress.done ? challenge.xp : 0, effectiveByNoon: byNoon)
            }
            day = day.next
        }
        return result
    }

    /// Total XP across all of history. See `days` for the parameters.
    public static func total(history: HydrationHistory, summaries: [DayKey: DaySummary], clock: DayClock,
                             factors: HydrationFactors, wakeMinutes: Int, sleepMinutes: Int = 23 * 60,
                             today: DayKey, repairs: Set<DayKey> = []) -> Int {
        days(history: history, summaries: summaries, clock: clock, factors: factors, wakeMinutes: wakeMinutes,
             sleepMinutes: sleepMinutes, today: today, repairs: repairs).values.reduce(0) { $0 + $1.total }
    }

    /// XP needed to go from `level` to the next: 1,000 at first, then 400 more
    /// for each level after, so early levels come quickly and late ones mean
    /// months of steady drinking.
    public static func cost(from level: Int) -> Int { 1000 + 400 * (max(level, 1) - 1) }

    /// Total XP at which `level` begins.
    public static func startXP(of level: Int) -> Int {
        let n = min(max(level, 1), maxLevel) - 1
        return 1000 * n + 200 * n * (n - 1)
    }

    public static func level(forXP xp: Int) -> LevelInfo {
        let xp = max(xp, 0)
        var level = 1
        while level < maxLevel, startXP(of: level + 1) <= xp { level += 1 }
        let start = startXP(of: level)
        let next = level < maxLevel ? startXP(of: level + 1) : start
        return LevelInfo(level: level, title: titles[level - 1], xp: xp, levelStartXP: start, nextLevelXP: next)
    }
}
