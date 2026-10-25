import Foundation

public struct RecapDay: Equatable, Sendable {
    public var key: DayKey
    public var effectiveML: Double

    public init(key: DayKey, effectiveML: Double) {
        self.key = key
        self.effectiveML = effectiveML
    }
}

/// The numbers for a month or year in review.
public struct Recap: Equatable, Sendable {
    /// "September 2026" or "2026".
    public var title: String
    public var from: DayKey
    public var to: DayKey
    /// Everything poured, before hydration factors.
    public var totalML: Double
    public var daysLogged: Int
    public var daysMet: Int
    /// The longest run of met days inside the range.
    public var bestRun: Int
    /// The drink with the most volume, and its share of `totalML` (0–1).
    public var favoriteDrink: DrinkKind?
    public var favoriteDrinkShare: Double
    /// Hour of the day (0–23) with the most volume.
    public var peakHour: Int?
    /// Mean effective intake per logged day.
    public var averageML: Double
    public var bestDay: RecapDay?
    /// `totalML` in 150-litre bathtubs.
    public var bathtubs: Double
    /// `totalML` in whole bottles of the person's own bottle size.
    public var bottles: Int

    public static let bathtubML = 150_000.0

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]

    /// The calendar month containing `day`.
    public static func month(containing day: DayKey, history: HydrationHistory, summaries: [DayKey: DaySummary],
                             clock: DayClock, bottleML: Double) -> Recap {
        let first = DayKey(year: day.year, month: day.month, day: 1)
        let nextMonth = day.month == 12 ? DayKey(year: day.year + 1, month: 1, day: 1)
                                        : DayKey(year: day.year, month: day.month + 1, day: 1)
        let name = monthNames.indices.contains(day.month - 1) ? monthNames[day.month - 1] : "\(day.month)"
        return make(title: "\(name) \(day.year)", from: first, to: nextMonth.previous, history: history,
                    summaries: summaries, clock: clock, bottleML: bottleML)
    }

    /// The calendar year.
    public static func year(_ year: Int, history: HydrationHistory, summaries: [DayKey: DaySummary],
                            clock: DayClock, bottleML: Double) -> Recap {
        make(title: "\(year)", from: DayKey(year: year, month: 1, day: 1), to: DayKey(year: year, month: 12, day: 31),
             history: history, summaries: summaries, clock: clock, bottleML: bottleML)
    }

    /// The month before the one containing `today`, for the recap shown on
    /// the first days of a new month.
    public static func previousMonth(of today: DayKey, history: HydrationHistory, summaries: [DayKey: DaySummary],
                                     clock: DayClock, bottleML: Double) -> Recap {
        month(containing: DayKey(year: today.year, month: today.month, day: 1).previous, history: history,
              summaries: summaries, clock: clock, bottleML: bottleML)
    }

    static func make(title: String, from: DayKey, to: DayKey, history: HydrationHistory,
                     summaries: [DayKey: DaySummary], clock: DayClock, bottleML: Double) -> Recap {
        var total = 0.0
        var effective = 0.0
        var logged = 0
        var met = 0
        var run = 0
        var bestRun = 0
        var best: RecapDay?
        var byDrink: [DrinkKind: Double] = [:]

        var day = from
        while day <= to {
            if let s = summaries[day], s.entryCount > 0 {
                logged += 1
                total += s.rawML
                effective += s.effectiveML
                for (kind, ml) in s.byDrink { byDrink[kind, default: 0] += ml }
                if best == nil || s.effectiveML > (best?.effectiveML ?? 0) {
                    best = RecapDay(key: day, effectiveML: s.effectiveML)
                }
            }
            if summaries[day]?.met == true {
                met += 1
                run += 1
                bestRun = max(bestRun, run)
            } else {
                run = 0
            }
            day = day.next
        }

        // Ties go to the first kind in `DrinkKind.allCases`.
        var favorite: DrinkKind?
        for kind in DrinkKind.allCases where (byDrink[kind] ?? 0) > (favorite.flatMap { byDrink[$0] } ?? 0) {
            favorite = kind
        }

        var byHour = [Double](repeating: 0, count: 24)
        for entry in HistoryMath.entries(from: clock.start(of: from), to: clock.end(of: to), in: history) {
            let hour = clock.calendar.component(.hour, from: entry.date)
            if byHour.indices.contains(hour) { byHour[hour] += entry.amountML }
        }
        var peak: Int?
        for hour in byHour.indices where byHour[hour] > (peak.map { byHour[$0] } ?? 0) { peak = hour }

        return Recap(title: title, from: from, to: to, totalML: total, daysLogged: logged, daysMet: met,
                     bestRun: bestRun, favoriteDrink: favorite,
                     favoriteDrinkShare: total > 0 ? (favorite.flatMap { byDrink[$0] } ?? 0) / total : 0,
                     peakHour: peak, averageML: logged > 0 ? effective / Double(logged) : 0, bestDay: best,
                     bathtubs: total / bathtubML, bottles: Int((total / max(bottleML, 1) + 1e-9).rounded(.down)))
    }
}
