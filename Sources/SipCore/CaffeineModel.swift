import Foundation

public struct CaffeinePoint: Equatable, Sendable {
    public var date: Date
    public var mg: Double

    public init(date: Date, mg: Double) {
        self.date = date
        self.mg = mg
    }
}

/// Caffeine still in the body. Each caffeinated drink is absorbed evenly over
/// 30 minutes, then halves every `halfLifeHours` (5 h by default; it ranges
/// from about 3 to 7 h between people). Pass the last 48 hours of entries so
/// yesterday's late coffee still counts.
public enum CaffeineModel {
    public static let absorptionMinutes = 30.0
    public static let defaultHalfLifeHours = 5.0

    struct Dose {
        var start: Date
        var mg: Double
    }

    /// Milligrams in the body at `date`.
    public static func level(at date: Date, entries: [Entry], rates: CaffeineRates,
                             halfLifeHours: Double = defaultHalfLifeHours) -> Double {
        let k = decayRate(halfLifeHours)
        return doses(entries, rates: rates).reduce(0) { $0 + amount($1, at: date, k: k) }
    }

    /// When the level drops below `threshold` for good, at or after `after`:
    /// later drinks (and ones still being absorbed) are taken into account.
    /// Nil if it's already below and nothing pending will lift it back over.
    public static func clearTime(below threshold: Double, after: Date, entries: [Entry], rates: CaffeineRates,
                                 halfLifeHours: Double = defaultHalfLifeHours) -> Date? {
        let all = doses(entries, rates: rates)
        guard threshold > 0, let lastStart = all.map(\.start).max() else { return nil }
        let k = decayRate(halfLifeHours)
        func level(_ date: Date) -> Double { all.reduce(0) { $0 + amount($1, at: date, k: k) } }
        let absorption = absorptionMinutes * 60

        // Once every drink is fully absorbed the level only falls, as a sum of
        // exponentials with the same rate, so the crossing has a closed form.
        let settled = max(lastStart.addingTimeInterval(absorption), after)
        let atSettled = level(settled)
        if atSettled >= threshold {
            return settled.addingTimeInterval(log(atSettled / threshold) / k)
        }
        guard settled > after else { return nil }

        // Already under by the time everything is absorbed: find the last
        // moment before that it was still over. Sample every 5 minutes plus
        // every dose's start and peak, where the curve can turn.
        var points: [Date] = [after, settled]
        var t = after.addingTimeInterval(300)
        while t < settled {
            points.append(t)
            t = t.addingTimeInterval(300)
        }
        for dose in all {
            for edge in [dose.start, dose.start.addingTimeInterval(absorption)] where edge > after && edge < settled {
                points.append(edge)
            }
        }
        points.sort()
        guard let high = points.lastIndex(where: { level($0) >= threshold }), high + 1 < points.count else { return nil }
        var low = points[high]
        var top = points[high + 1]
        for _ in 0..<40 where top.timeIntervalSince(low) > 0.5 {
            let mid = low.addingTimeInterval(top.timeIntervalSince(low) / 2)
            if level(mid) >= threshold { low = mid } else { top = mid }
        }
        return top
    }

    /// The level every `step` seconds from `from` to `to`, both included.
    /// Capped at 10,000 points.
    public static func curve(from: Date, to: Date, step: TimeInterval = 600, entries: [Entry], rates: CaffeineRates,
                             halfLifeHours: Double = defaultHalfLifeHours) -> [CaffeinePoint] {
        guard step > 0, to >= from else { return [] }
        let all = doses(entries, rates: rates)
        let k = decayRate(halfLifeHours)
        let count = min(Int(to.timeIntervalSince(from) / step), 9_999) + 1
        return (0..<count).map { i in
            let date = from.addingTimeInterval(Double(i) * step)
            return CaffeinePoint(date: date, mg: all.reduce(0) { $0 + amount($1, at: date, k: k) })
        }
    }

    /// What would be left at `bedtime` if `mg` more were drunk at `date`: the
    /// "is this coffee a good idea?" number.
    public static func levelAtBedtime(ifAdding mg: Double, at date: Date, bedtime: Date, entries: [Entry],
                                      rates: CaffeineRates, halfLifeHours: Double = defaultHalfLifeHours) -> Double {
        let k = decayRate(halfLifeHours)
        return level(at: bedtime, entries: entries, rates: rates, halfLifeHours: halfLifeHours)
            + amount(Dose(start: date, mg: max(mg, 0)), at: bedtime, k: k)
    }

    // MARK: - Model

    static func doses(_ entries: [Entry], rates: CaffeineRates) -> [Dose] {
        entries.compactMap { entry in
            let mg = rates.milligrams(entry)
            return mg > 0 ? Dose(start: entry.date, mg: mg) : nil
        }
    }

    /// Per-second decay constant. Half-lives under 6 minutes are treated as 6.
    static func decayRate(_ halfLifeHours: Double) -> Double {
        log(2) / (max(halfLifeHours, 0.1) * 3600)
    }

    static func amount(_ dose: Dose, at date: Date, k: Double) -> Double {
        let t = date.timeIntervalSince(dose.start)
        guard t > 0 else { return 0 }
        let absorption = absorptionMinutes * 60
        if t < absorption { return dose.mg * t / absorption }
        return dose.mg * exp(-k * (t - absorption))
    }
}
