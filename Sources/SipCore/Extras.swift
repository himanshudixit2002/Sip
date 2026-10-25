import Foundation

// MARK: - Caffeine

/// Caffeine per millilitre for each drink. Defaults are typical values (about
/// 95 mg in a 240 ml coffee, 47 mg in a 240 ml black tea) and can be changed.
public struct CaffeineRates: Codable, Equatable, Sendable {
    public var mgPerML: [DrinkKind: Double]

    public static let defaults: [DrinkKind: Double] = [.coffee: 0.40, .tea: 0.20]

    public init(mgPerML: [DrinkKind: Double] = [:]) {
        self.mgPerML = mgPerML
    }

    public subscript(kind: DrinkKind) -> Double {
        get { mgPerML[kind] ?? CaffeineRates.defaults[kind] ?? 0 }
        set { mgPerML[kind] = max(newValue, 0) }
    }

    public func milligrams(in entries: [Entry]) -> Double {
        entries.reduce(0) { $0 + $1.amountML * self[$1.drink] }
    }

    public func milligrams(_ entry: Entry) -> Double { entry.amountML * self[entry.drink] }
}

public enum CaffeineCheck: Equatable, Sendable {
    case fine
    case afterCutoff
    case overLimit(mg: Double)
}

public enum Caffeine {
    /// Whether a caffeinated drink logged at `date` deserves a gentle warning.
    /// `cutoffMinutes` is minutes past midnight.
    public static func check(entry: Entry, todayEntries: [Entry], rates: CaffeineRates,
                             cutoffMinutes: Int, limitMG: Double, calendar: Calendar) -> CaffeineCheck {
        guard rates[entry.drink] > 0 else { return .fine }
        let total = rates.milligrams(in: todayEntries)
        if limitMG > 0, total > limitMG { return .overLimit(mg: total) }
        let c = calendar.dateComponents([.hour, .minute], from: entry.date)
        let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        // A drink after the cutoff but before 4 am still counts as "late".
        if minutes >= cutoffMinutes || minutes < 4 * 60 { return .afterCutoff }
        return .fine
    }
}

// MARK: - Refills

/// Progress measured in refills of a physical bottle: "2 of 4".
public struct RefillProgress: Equatable, Sendable {
    public var bottleML: Double
    public var finished: Int
    public var needed: Int
    /// How far through the current bottle, 0–1.
    public var current: Double

    public init(bottleML: Double, consumedML: Double, goalML: Double) {
        let bottle = max(bottleML, 50)
        self.bottleML = bottle
        finished = Int((consumedML + 0.5) / bottle)
        needed = max(Int((goalML / bottle).rounded(.up)), 1)
        current = (consumedML - Double(finished) * bottle) / bottle
    }

    /// "2 of 4 bottles".
    public var label: String { "\(finished) of \(needed) \(needed == 1 ? "bottle" : "bottles")" }

    /// "2/4", for the widget's smallest sizes.
    public var shortLabel: String { "\(finished)/\(needed)" }
}

// MARK: - Heat

public enum HeatAdjustment {
    /// Extra water for the day from the forecast high, in °C.
    public static func bonusML(maxTemperatureC t: Double) -> Double {
        switch t {
        case ..<25: return 0
        case ..<30: return 250
        case ..<35: return 500
        default: return 750
        }
    }
}

// MARK: - Weekly summary

/// The Sunday-evening notification. The numbers come from `WeekStats` so the
/// notification, the share card and Insights can't disagree.
public struct WeeklySummary: Equatable, Sendable {
    public var totalML: Double
    public var averageML: Double
    public var metDays: Int
    public var best: DaySummary?
    public var streak: Int

    /// The seven drinking days ending with `last`.
    public init(summaries: [DayKey: DaySummary], last: DayKey, streak: Int) {
        let stats = WeekStats(summaries: summaries, last: last, count: 7)
        totalML = stats.totalML
        averageML = stats.averageML
        metDays = stats.metCount
        best = stats.bestDay
        self.streak = streak
    }

    public func text(unit: VolumeUnit) -> (title: String, body: String) {
        let title = metDays >= 6 ? "Great week: goal hit \(metDays) of 7 days"
                                 : "Your week: goal hit \(metDays) of 7 days"
        var parts = ["\(Volume.formatCompact(totalML, unit)) in total", "\(Volume.formatCompact(averageML, unit)) a day on average"]
        if let best, best.effectiveML > 0 { parts.append("best day \(Volume.formatCompact(best.effectiveML, unit))") }
        if streak > 1 { parts.append("\(streak)-day streak") }
        return (title, parts.joined(separator: " · ") + ".")
    }
}

// MARK: - Inbox

/// Lines dropped into the inbox file by an iPhone Shortcut or anything else.
///
/// Accepted forms, one per line:
/// - `2026-10-06T10:00:00+05:30,250,tea` (the CSV export format)
/// - `250`, `330 tea`, `1.5 l`, `12 oz coffee`, `glass`, `2 bottles`
///   (logged at the moment the line is read)
public enum Inbox {
    public static func parse(_ text: String, now: Date, cups: [QuickLogCup], unit: VolumeUnit) -> (entries: [Entry], skipped: Int) {
        var entries: [Entry] = []
        var skipped = 0
        for raw in text.split(whereSeparator: \.isNewline) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if line.contains(","), let first = HistoryCSV.parse(line).entries.first {
                entries.append(first)
            } else if let parsed = QuickLogParser.parse(line, cups: cups, unit: unit) {
                entries.append(Entry(date: now, amountML: parsed.ml, drink: parsed.drink ?? .water))
            } else {
                skipped += 1
            }
        }
        return (entries, skipped)
    }
}
