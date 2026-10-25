import Foundation

/// A checkpoint on the bottle: "by 1 PM you'd ideally be at 43%".
public struct TimeMark: Equatable, Sendable {
    /// Minutes past the midnight that starts the waking day. Marks after a
    /// past-midnight bedtime run past 1440 (1 AM is 1500).
    public var minutes: Int
    /// Share of the goal you'd have drunk by then on an even pace, 0–1.
    public var fraction: Double
    /// "9 AM".
    public var label: String

    public init(minutes: Int, fraction: Double, label: String) {
        self.minutes = minutes
        self.fraction = fraction
        self.label = label
    }
}

public enum TimeMarkers {
    /// Marks on round hours through the waking day: the first whole hour at
    /// least an hour after waking, then every `everyMinutes`, up to bedtime.
    /// The fractions use the same curve as `Pace.expectedFraction`, so the
    /// marks line up with the pace status.
    public static func marks(wakeMinutes: Int, sleepMinutes: Int, everyMinutes: Int = 120) -> [TimeMark] {
        let wake = ((wakeMinutes % 1440) + 1440) % 1440
        var sleep = ((sleepMinutes % 1440) + 1440) % 1440
        if sleep <= wake { sleep += 1440 }
        let step = max(everyMinutes, 30)
        let hours = ActiveHours(wakeMinutes: wake, sleepMinutes: sleep % 1440)
        let day = referenceDay
        var marks: [TimeMark] = []
        var minute = Int((Double(wake + 60) / 60).rounded(.up)) * 60
        while minute <= sleep {
            let date = referenceClock.time(minute, on: day)
            let fraction = min(Pace.expectedFraction(at: date, on: day, hours: hours, clock: referenceClock), 1)
            marks.append(TimeMark(minutes: minute, fraction: fraction, label: clockLabel(minute)))
            minute += step
        }
        return marks
    }

    /// The first mark still ahead of `nowMinutes`, counted the same way as
    /// `TimeMark.minutes` (add 1440 after midnight if bedtime is later).
    public static func nextMark(_ marks: [TimeMark], nowMinutes: Int) -> TimeMark? {
        marks.first { $0.minutes > nowMinutes }
    }

    /// A fixed day in UTC with midnight boundaries, so the pace curve can be
    /// sampled without time zones or daylight saving getting involved.
    private static let referenceClock: DayClock = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
        return DayClock(dayStartHour: 0, calendar: calendar)
    }()
    private static let referenceDay = DayKey(year: 2001, month: 1, day: 1)
}

/// "9 AM", "12 PM", "9:30 PM" for minutes past midnight (wrapping past 24 h).
/// Written by hand so the label is the same in every locale and test run.
func clockLabel(_ minutes: Int) -> String {
    let m = ((minutes % 1440) + 1440) % 1440
    let hour = m / 60
    let minute = m % 60
    let twelve = hour % 12 == 0 ? 12 : hour % 12
    let suffix = hour < 12 ? "AM" : "PM"
    return minute == 0 ? "\(twelve) \(suffix)" : "\(twelve):\(minute < 10 ? "0" : "")\(minute) \(suffix)"
}
