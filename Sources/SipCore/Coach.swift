import Foundation

public struct CoachTip: Equatable, Sendable, Identifiable {
    /// The rule that produced it, e.g. "lateHeavy".
    public var id: String
    /// SF Symbol name.
    public var symbol: String
    public var title: String
    public var detail: String
    /// How strongly the data backs the tip, roughly 0–1. Tips are sorted by it.
    public var weight: Double

    public init(id: String, symbol: String, title: String, detail: String, weight: Double) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.detail = detail
        self.weight = weight
    }
}

public struct GoalSuggestion: Equatable, Sendable {
    public var goalML: Double
    public var reason: String

    public init(goalML: Double, reason: String) {
        self.goalML = goalML
        self.reason = reason
    }
}

/// Plain rules over the last four weeks that turn patterns into advice. Each
/// rule needs enough data and a clear signal before it speaks, so a quiet
/// coach means nothing stood out, not that it's broken.
public enum Coach {
    public static let windowDays = 28
    public static let minimumLoggedDays = 7

    /// Tips for the 28 finished days before `today`, strongest first. Empty
    /// until at least 7 of those days have entries.
    public static func tips(history: HydrationHistory, summaries: [DayKey: DaySummary], clock: DayClock,
                            factors: HydrationFactors, wakeMinutes: Int, sleepMinutes: Int, today: DayKey,
                            unit: VolumeUnit = .milliliters) -> [CoachTip] {
        let keys = (1...windowDays).reversed().map { today.adding(days: -$0) }
        guard let firstKey = keys.first else { return [] }
        let slice = HistoryMath.entries(from: clock.start(of: firstKey), to: clock.start(of: today), in: history)
        let byDay = HistoryMath.entriesByDay(slice, clock: clock)
        let logged = keys.compactMap { key -> (summary: DaySummary, entries: [Entry])? in
            guard let summary = summaries[key], summary.entryCount > 0, let entries = byDay[key], !entries.isEmpty
            else { return nil }
            return (summary, entries)
        }
        guard logged.count >= minimumLoggedDays else { return [] }

        let hours = ActiveHours(wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes)
        func ml(_ value: Double) -> String { Volume.formatCompact(value, unit) }
        func percent(_ share: Double) -> Int { Int((share * 100).rounded()) }
        var tips: [CoachTip] = []

        // Late heavy: most of the day's water after 4 PM.
        var total = 0.0
        var late = 0.0
        for day in logged {
            let four = clock.time(16 * 60, on: day.summary.key)
            for entry in day.entries {
                let value = entry.effectiveML(factors)
                total += value
                if entry.date >= four { late += value }
            }
        }
        if total > 0, late / total >= 0.55 {
            let share = late / total
            tips.append(CoachTip(id: "lateHeavy", symbol: "sunrise.fill", title: "Front-load your day",
                                 detail: "\(percent(share))% of your water comes after 4 PM. A big glass soon after waking and another before lunch spread it out.",
                                 weight: min(1, 0.5 + (share - 0.55) * 2)))
        }

        // Weekend dip.
        let weekend = logged.filter { $0.summary.key.weekday == 1 || $0.summary.key.weekday == 7 }.map(\.summary.effectiveML)
        let weekday = logged.filter { $0.summary.key.weekday != 1 && $0.summary.key.weekday != 7 }.map(\.summary.effectiveML)
        if weekend.count >= 2, weekday.count >= 4, let weekendMean = mean(weekend), let weekdayMean = mean(weekday),
           weekdayMean > 0, weekendMean <= weekdayMean * 0.8 {
            let ratio = weekendMean / weekdayMean
            tips.append(CoachTip(id: "weekendDip", symbol: "calendar", title: "Weekends slip",
                                 detail: "Weekends average \(ml(weekendMean)), against \(ml(weekdayMean)) on weekdays. Keep a bottle with you on Saturdays and Sundays.",
                                 weight: min(1, 0.4 + (0.8 - ratio) * 2)))
        }

        // Coffee days: less plain water on days with coffee.
        func water(_ s: DaySummary) -> Double { (s.byDrink[.water] ?? 0) + (s.byDrink[.sparkling] ?? 0) }
        let coffee = logged.filter { ($0.summary.byDrink[.coffee] ?? 0) > 0 }.map { water($0.summary) }
        let noCoffee = logged.filter { ($0.summary.byDrink[.coffee] ?? 0) <= 0 }.map { water($0.summary) }
        if coffee.count >= 3, noCoffee.count >= 3, let withCoffee = mean(coffee), let without = mean(noCoffee),
           without - withCoffee >= 300 {
            let gap = without - withCoffee
            tips.append(CoachTip(id: "coffeeDays", symbol: "mug.fill", title: "Coffee crowds out water",
                                 detail: "On days with coffee you drink \(ml(gap)) less water. Try a glass of water alongside each cup.",
                                 weight: min(1, 0.4 + (gap - 300) / 1000)))
        }

        // Morning start: an early first drink goes with better days.
        var earlyMet: [Bool] = []
        var lateMet: [Bool] = []
        for day in logged {
            let wake = hours.window(on: day.summary.key, clock: clock).wake
            guard let first = day.entries.first?.date else { continue }
            if first <= wake.addingTimeInterval(3600) { earlyMet.append(day.summary.met) } else { lateMet.append(day.summary.met) }
        }
        if earlyMet.count >= 3, lateMet.count >= 3 {
            let earlyRate = Double(earlyMet.filter { $0 }.count) / Double(earlyMet.count)
            let lateRate = Double(lateMet.filter { $0 }.count) / Double(lateMet.count)
            if earlyRate - lateRate >= 0.25 {
                tips.append(CoachTip(id: "morningStart", symbol: "alarm.fill", title: "Start in the first hour",
                                     detail: "You reach your goal on \(percent(earlyRate))% of days that begin with a drink within an hour of waking, and \(percent(lateRate))% of the others. Keep a glass by the bed.",
                                     weight: min(1, 0.4 + (earlyRate - lateRate - 0.25))))
            }
        }

        // Long gaps between drinks while awake.
        var longest: [Double] = []
        for day in logged {
            let window = hours.window(on: day.summary.key, clock: clock)
            let times = day.entries.map(\.date).filter { $0 >= window.wake && $0 <= window.sleep }
            guard times.count >= 2 else { continue }
            longest.append(zip(times, times.dropFirst()).map { $1.timeIntervalSince($0) }.max() ?? 0)
        }
        if longest.count >= 5, let gap = median(longest), gap >= 4 * 3600 {
            let hoursText = String(format: "%.1f", gap / 3600)
            tips.append(CoachTip(id: "longGaps", symbol: "hourglass", title: "Mind the gap",
                                 detail: "On a typical day your longest stretch without a drink is \(hoursText) hours. A reminder every 90 minutes would break it up.",
                                 weight: min(1, 0.4 + (gap / 3600 - 4) / 4)))
        }

        // Big gulps.
        if let typical = median(logged.flatMap { $0.entries.map(\.amountML) }), typical >= 500 {
            tips.append(CoachTip(id: "bigGulps", symbol: "drop.triangle.fill", title: "Smaller, more often",
                                 detail: "Your typical drink is \(ml(typical)). Smaller glasses through the day are easier on the body and keep you steadier.",
                                 weight: min(1, 0.3 + (typical - 500) / 1000)))
        }

        // Consistency: a positive note, counted from the first logged day.
        if let start = logged.first?.summary.key {
            let span = start.days(to: today)
            let met = logged.filter { $0.summary.met }.count
            let rate = span > 0 ? Double(met) / Double(span) : 0
            if span >= minimumLoggedDays, rate >= 0.85 {
                tips.append(CoachTip(id: "consistent", symbol: "star.fill", title: "Rock-solid routine",
                                     detail: "You've hit your goal on \(met) of the last \(span) days. Keep it up!",
                                     weight: 0.2 + (rate - 0.85)))
            }
        }

        return tips.sorted { $0.weight != $1.weight ? $0.weight > $1.weight : $0.id < $1.id }
    }

    /// A new goal when the last 14 finished days point to one: a step up after
    /// two easy weeks, or a lower stepping stone after a hard fortnight. Nil
    /// when the current goal fits or there's too little data (under 7 logged
    /// days).
    public static func goalSuggestion(summaries: [DayKey: DaySummary], today: DayKey, goal: Double,
                                      unit: VolumeUnit = .milliliters) -> GoalSuggestion? {
        let logged = (1...14).compactMap { summaries[today.adding(days: -$0)] }.filter { $0.entryCount > 0 }
        guard logged.count >= minimumLoggedDays, goal > 0 else { return nil }
        let met = logged.filter(\.met).count
        let meanProgress = mean(logged.map(\.progress)) ?? 0
        let meanEffective = mean(logged.map(\.effectiveML)) ?? 0

        if met >= 12, meanProgress >= 1.15 {
            let next = goal + 250
            return GoalSuggestion(goalML: next,
                                  reason: "You've met your goal on \(met) of the last 14 days, averaging \(Int((meanProgress * 100).rounded()))% of it. Ready to aim for \(Volume.formatCompact(next, unit))?")
        }
        if met <= 5 {
            let stone = max((meanEffective * 1.1 / 250).rounded() * 250, 1500)
            guard stone < goal else { return nil }
            return GoalSuggestion(goalML: stone,
                                  reason: "You've met your goal on \(met) of the last 14 days. A stepping-stone goal of \(Volume.formatCompact(stone, unit)), a little above your recent \(Volume.formatCompact(meanEffective, unit)) a day, is one you can hit every day.")
        }
        return nil
    }

    static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 0 ? (sorted[mid - 1] + sorted[mid]) / 2 : sorted[mid]
    }
}
