import Foundation

public enum ChallengeKind: String, Codable, CaseIterable, Sendable {
    /// A set amount before noon.
    case morningAmount
    /// A number of separate drinks.
    case manySips
    /// The whole goal by a set hour.
    case goalBy
    /// No coffee or tea after 2 PM, and the goal met.
    case noLateCaffeine
    /// Only water or sparkling, and most of the goal.
    case waterOnly
    /// A drink in several different clock hours.
    case steadyHours
    /// More than yesterday. Only offered when yesterday had something.
    case beatYesterday
    /// A first drink soon after waking.
    case earlyStart
}

/// One small goal for the day, sized from the person's own numbers so it's
/// always achievable.
public struct Challenge: Equatable, Codable, Sendable {
    public var kind: ChallengeKind
    public var title: String
    public var detail: String
    /// SF Symbol name.
    public var symbol: String
    /// What the challenge is measured against, in the kind's own terms:
    /// millilitres for `morningAmount`, `noLateCaffeine`, `waterOnly` and
    /// `beatYesterday`; a count for `manySips` and `steadyHours`; the hour
    /// (0–23) for `goalBy`; minutes after waking for `earlyStart`.
    public var target: Double
    public var xp: Int

    public init(kind: ChallengeKind, title: String, detail: String, symbol: String, target: Double, xp: Int) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.target = target
        self.xp = xp
    }
}

public struct ChallengeProgress: Equatable, Sendable {
    public var challenge: Challenge
    /// 0–1.
    public var fraction: Double
    public var done: Bool
    /// The challenge can no longer be completed today.
    public var failed: Bool
    public var text: String
}

public enum Challenges {
    public static let noonHour = 12
    public static let caffeineCutoffHour = 14
    public static let steadyHoursTarget = 6
    public static let earlyStartMinutes = 60

    /// Today's challenge. The kind comes from the date alone, so it's the same
    /// on every launch and every Mac, changes each day, and never repeats on
    /// two days running. The numbers come from the person's goal and hours.
    public static func challenge(for day: DayKey, goal: Double, wakeMinutes: Int, sleepMinutes: Int,
                                 yesterdayML: Double, unit: VolumeUnit = .milliliters) -> Challenge {
        let kind = Self.kind(for: day, yesterdayML: yesterdayML)
        let n = dayNumber(day)
        switch kind {
        case .morningAmount:
            let amount = max((goal * 0.4 / 50).rounded() * 50, 50)
            return Challenge(kind: kind, title: "Morning Boost",
                             detail: "Drink \(Volume.formatCompact(amount, unit)) before noon.",
                             symbol: "sunrise.fill", target: amount, xp: 50)
        case .manySips:
            var random = SeededRandom(seed: n, salt: 1)
            let count = 6 + Int(random.next() % 3)
            return Challenge(kind: kind, title: "Little and Often",
                             detail: "Have \(count) separate drinks today.",
                             symbol: "circle.grid.3x3.fill", target: Double(count), xp: 40 + (count - 6) * 5)
        case .goalBy:
            let hour = goalByHour(wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes)
            return Challenge(kind: kind, title: "Beat the Clock",
                             detail: "Reach your goal by \(clockLabel(hour * 60)).",
                             symbol: "alarm.fill", target: Double(hour), xp: 80 - (hour - 17) * 5)
        case .noLateCaffeine:
            return Challenge(kind: kind, title: "Calm Evening",
                             detail: "No coffee or tea after \(clockLabel(caffeineCutoffHour * 60)), and reach your goal.",
                             symbol: "moon.zzz.fill", target: goal, xp: 60)
        case .waterOnly:
            let amount = goal * 0.6
            return Challenge(kind: kind, title: "Pure Water Day",
                             detail: "Only water or sparkling today, and at least \(Volume.formatCompact(amount, unit)).",
                             symbol: "drop.fill", target: amount, xp: 60)
        case .steadyHours:
            return Challenge(kind: kind, title: "Steady Flow",
                             detail: "Drink in \(steadyHoursTarget) different hours of the day.",
                             symbol: "clock.fill", target: Double(steadyHoursTarget), xp: 55)
        case .beatYesterday:
            return Challenge(kind: kind, title: "Top Yesterday",
                             detail: "Drink more than yesterday's \(Volume.formatCompact(yesterdayML, unit)).",
                             symbol: "chart.line.uptrend.xyaxis", target: yesterdayML, xp: 60)
        case .earlyStart:
            let by = (wakeMinutes + earlyStartMinutes) % (24 * 60)
            return Challenge(kind: kind, title: "Early Start",
                             detail: "Have your first drink within an hour of waking, by \(clockLabel(by)).",
                             symbol: "sun.max.fill", target: Double(earlyStartMinutes), xp: 40)
        }
    }

    /// The kind of challenge on `day`.
    ///
    /// Days are taken in blocks of seven, each a shuffled deck of the eight
    /// kinds, so a week never repeats a kind. Where one block's last day would
    /// match the next block's first, the next block swaps in its spare kind.
    /// `beatYesterday` after an empty day is swapped for a kind that differs
    /// from both neighbours.
    public static func kind(for day: DayKey, yesterdayML: Double) -> ChallengeKind {
        let n = dayNumber(day)
        let natural = naturalKind(n)
        guard natural == .beatYesterday, !(yesterdayML > 0) else { return natural }
        let avoid: Set<ChallengeKind> = [.beatYesterday, naturalKind(n - 1), naturalKind(n + 1)]
        return shuffledKinds(seed: n, salt: 2).first { !avoid.contains($0) } ?? .manySips
    }

    /// How the challenge is going. `entries` are the day's entries; any
    /// outside the day are ignored.
    public static func progress(_ challenge: Challenge, entries: [Entry], day: DayKey, clock: DayClock, goal: Double,
                                yesterdayML: Double, factors: HydrationFactors, wakeMinutes: Int, now: Date,
                                unit: VolumeUnit = .milliliters) -> ChallengeProgress {
        let start = clock.start(of: day)
        let end = clock.end(of: day)
        let entries = entries.filter { $0.date >= start && $0.date < end }.sorted { $0.date < $1.date }
        let effective = entries.reduce(0) { $0 + $1.effectiveML(factors) }
        func ml(_ value: Double) -> String { Volume.formatCompact(value, unit) }
        func ratio(_ value: Double, _ target: Double) -> Double {
            target > 0 ? min(max(value / target, 0), 1) : (value > 0 ? 1 : 0)
        }
        func result(_ fraction: Double, done: Bool, failed: Bool = false, _ text: String) -> ChallengeProgress {
            ChallengeProgress(challenge: challenge, fraction: done ? 1 : fraction, done: done,
                              failed: failed && !done, text: text)
        }

        switch challenge.kind {
        case .morningAmount:
            let noon = clock.time(noonHour * 60, on: day)
            let before = entries.reduce(0) { $1.date < noon ? $0 + $1.effectiveML(factors) : $0 }
            let done = before >= challenge.target - 0.5
            if done { return result(1, done: true, "Done: \(ml(before)) before noon") }
            let late = now >= noon
            return result(ratio(before, challenge.target), done: false, failed: late,
                          late ? "Missed: \(ml(before)) of \(ml(challenge.target)) by noon"
                               : "\(ml(before)) of \(ml(challenge.target)) before noon")

        case .manySips:
            let target = Int(challenge.target)
            let done = entries.count >= target
            return result(ratio(Double(entries.count), challenge.target), done: done,
                          done ? "Done: \(entries.count) drinks" : "\(entries.count) of \(target) drinks")

        case .goalBy:
            let hour = Int(challenge.target)
            let deadline = clock.time(hour * 60, on: day)
            let before = entries.reduce(0) { $1.date < deadline ? $0 + $1.effectiveML(factors) : $0 }
            let done = goal > 0 && before >= goal - 0.5
            if done { return result(1, done: true, "Done: goal reached before \(clockLabel(hour * 60))") }
            let late = now >= deadline
            return result(ratio(before, goal), done: false, failed: late,
                          late ? "Missed: \(ml(before)) of \(ml(goal)) by \(clockLabel(hour * 60))"
                               : "\(ml(before)) of \(ml(goal)) by \(clockLabel(hour * 60))")

        case .noLateCaffeine:
            let cutoff = clock.time(caffeineCutoffHour * 60, on: day)
            let lateCaffeine = entries.contains { ($0.drink == .coffee || $0.drink == .tea) && $0.date >= cutoff }
            if lateCaffeine {
                return result(ratio(effective, goal), done: false, failed: true,
                              "Missed: coffee or tea after \(clockLabel(caffeineCutoffHour * 60))")
            }
            let done = goal > 0 && effective >= goal - 0.5
            return result(ratio(effective, goal), done: done,
                          done ? "Done: goal reached, no late caffeine"
                               : "\(ml(effective)) of \(ml(goal)), no caffeine after \(clockLabel(caffeineCutoffHour * 60))")

        case .waterOnly:
            if entries.contains(where: { $0.drink != .water && $0.drink != .sparkling }) {
                return result(ratio(effective, challenge.target), done: false, failed: true,
                              "Missed: something other than water today")
            }
            let done = effective >= challenge.target - 0.5
            return result(ratio(effective, challenge.target), done: done,
                          done ? "Done: \(ml(effective)) of pure water"
                               : "\(ml(effective)) of \(ml(challenge.target)), water only")

        case .steadyHours:
            let hours = Set(entries.map { clock.calendar.component(.hour, from: $0.date) }).count
            let target = Int(challenge.target)
            let done = hours >= target
            return result(ratio(Double(hours), challenge.target), done: done,
                          done ? "Done: drinks in \(hours) different hours" : "\(hours) of \(target) hours")

        case .beatYesterday:
            let done = effective > yesterdayML + 0.5
            return result(yesterdayML > 0 ? min(effective / yesterdayML, 1) : (effective > 0 ? 1 : 0), done: done,
                          done ? "Done: \(ml(effective)), more than yesterday"
                               : "\(ml(effective)) of yesterday's \(ml(yesterdayML))")

        case .earlyStart:
            let wake = ActiveHours(wakeMinutes: wakeMinutes).window(on: day, clock: clock).wake
            let deadline = wake.addingTimeInterval(challenge.target * 60)
            let done = entries.first.map { $0.date <= deadline } ?? false
            if done { return result(1, done: true, "Done: first drink by \(clockLabel(minutes(deadline, clock)))") }
            let late = now > deadline || !entries.isEmpty
            return result(0, done: false, failed: late,
                          late ? "Missed: no drink by \(clockLabel(minutes(deadline, clock)))"
                               : "First drink by \(clockLabel(minutes(deadline, clock)))")
        }
    }

    /// Every day whose challenge was completed, for badges.
    public static func completedDays(history: HydrationHistory, summaries: [DayKey: DaySummary], clock: DayClock,
                                     factors: HydrationFactors, wakeMinutes: Int, sleepMinutes: Int) -> Set<DayKey> {
        let byDay = HistoryMath.entriesByDay(history.entries, clock: clock)
        var result: Set<DayKey> = []
        for (day, summary) in summaries where summary.entryCount > 0 {
            let yesterday = summaries[day.previous]?.effectiveML ?? 0
            let challenge = Self.challenge(for: day, goal: summary.goalML, wakeMinutes: wakeMinutes,
                                           sleepMinutes: sleepMinutes, yesterdayML: yesterday)
            let p = Self.progress(challenge, entries: byDay[day] ?? [], day: day, clock: clock, goal: summary.goalML,
                             yesterdayML: yesterday, factors: factors, wakeMinutes: wakeMinutes, now: clock.end(of: day))
            if p.done { result.insert(day) }
        }
        return result
    }

    /// Three hours before sleep, kept between 5 PM and 9 PM. A sleep time
    /// earlier than wake means after midnight.
    static func goalByHour(wakeMinutes: Int, sleepMinutes: Int) -> Int {
        var sleep = sleepMinutes
        if sleep <= wakeMinutes { sleep += 24 * 60 }
        return min(max(sleep / 60 - 3, 17), 21)
    }

    // MARK: - Deterministic choice

    /// Days since 1 January 2000.
    static func dayNumber(_ day: DayKey) -> Int { DayKey(year: 2000, month: 1, day: 1).days(to: day) }

    static func naturalKind(_ n: Int) -> ChallengeKind {
        let week = n >= 0 ? n / 7 : (n - 6) / 7
        let position = n - week * 7
        var deck = shuffledKinds(seed: week, salt: 0)
        if deck[0] == shuffledKinds(seed: week - 1, salt: 0)[6] { deck.swapAt(0, deck.count - 1) }
        return deck[position]
    }

    /// The kinds in an order fixed by `seed`. Shuffled by hand rather than
    /// with `shuffle(using:)`, whose algorithm the standard library may change.
    private static func shuffledKinds(seed: Int, salt: UInt64) -> [ChallengeKind] {
        var random = SeededRandom(seed: seed, salt: salt)
        var kinds = ChallengeKind.allCases
        for i in stride(from: kinds.count - 1, to: 0, by: -1) {
            kinds.swapAt(i, Int(random.next() % UInt64(i + 1)))
        }
        return kinds
    }

    private static func minutes(_ date: Date, _ clock: DayClock) -> Int {
        let c = clock.calendar.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

/// SplitMix64: tiny, fast and identical on every machine, unlike `Hasher`,
/// which is seeded differently on each launch.
struct SeededRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: Int, salt: UInt64 = 0) {
        state = UInt64(bitPattern: Int64(seed)) &* 0x9E37_79B9_7F4A_7C15 ^ (salt &+ 0x5151_C0DE_D00D_F00D)
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

// MARK: - Comeback

/// A missed day can be won back: drink at least 110% of the goal the next day
/// and the miss counts as met for streaks. Only one comeback per calendar
/// month, so it rescues a bad day without replacing the habit.
public enum Comeback {
    public static let factor = 1.1

    /// Repaired days, earliest first in each month wins. A missed day is one
    /// with an unmet summary, or a day with no entries between the first
    /// logged day and today. Today can repair yesterday, but today itself is
    /// never repaired since it isn't over.
    public static func repairs(summaries: [DayKey: DaySummary], today: DayKey) -> Set<DayKey> {
        guard let first = summaries.keys.min() else { return [] }
        var result: Set<DayKey> = []
        var usedMonths: Set<Int> = []
        var day = first
        while day < today {
            let next = day.next
            let month = day.year * 12 + day.month
            if summaries[day]?.met != true, !usedMonths.contains(month),
               let after = summaries[next], after.goalML > 0,
               after.effectiveML >= after.goalML * factor - 0.5 {
                result.insert(day)
                usedMonths.insert(month)
            }
            day = next
        }
        return result
    }
}
