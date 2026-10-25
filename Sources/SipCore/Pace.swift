import Foundation

/// The part of the day you're awake, as wall-clock minutes past midnight.
/// `sleep` may be earlier than `wake` to mean "after midnight".
public struct ActiveHours: Codable, Equatable, Sendable {
    public var wakeMinutes: Int
    public var sleepMinutes: Int

    public init(wakeMinutes: Int = 7 * 60, sleepMinutes: Int = 23 * 60) {
        self.wakeMinutes = wakeMinutes
        self.sleepMinutes = sleepMinutes
    }

    /// The awake window belonging to drinking day `key`.
    public func window(on key: DayKey, clock: DayClock) -> (wake: Date, sleep: Date) {
        var wake = clock.time(wakeMinutes, on: key)
        // A wake time before the day boundary (say 03:00 with days starting at
        // 04:00) belongs to the next calendar date.
        if wake < clock.start(of: key) { wake = clock.time(wakeMinutes, on: key.next) }
        var sleep = clock.time(sleepMinutes, on: key)
        while sleep <= wake { sleep = sleep.addingTimeInterval(24 * 3600) }
        return (wake, sleep)
    }
}

public enum PaceStatus: Equatable, Sendable {
    case goalMet
    case ahead(ml: Double)
    case onTrack
    case behind(ml: Double)
    case notStarted   // before wake time
}

public enum Pace {
    /// Share of the day's goal you'd have drunk by `date` if you spread it
    /// evenly across your waking hours.
    public static func expectedFraction(at date: Date, on key: DayKey, hours: ActiveHours, clock: DayClock) -> Double {
        let window = hours.window(on: key, clock: clock)
        let span = window.sleep.timeIntervalSince(window.wake)
        guard span > 0 else { return 1 }
        return min(max(date.timeIntervalSince(window.wake) / span, 0), 1)
    }

    /// The tolerance either side of the ideal line that still counts as on
    /// track: 5% of the goal, never less than 100 ml.
    public static func tolerance(goal: Double) -> Double { max(goal * 0.05, 100) }

    public static func status(consumed: Double, goal: Double, expectedFraction: Double) -> PaceStatus {
        if goal > 0, consumed >= goal - 0.5 { return .goalMet }
        if expectedFraction <= 0 { return consumed > 0 ? .ahead(ml: consumed) : .notStarted }
        let expected = goal * expectedFraction
        let slack = tolerance(goal: goal)
        if consumed < expected - slack { return .behind(ml: expected - consumed) }
        if consumed > expected + slack { return .ahead(ml: consumed - expected) }
        return .onTrack
    }

    /// The moment the ideal line catches up with what you've drunk, i.e. when
    /// you'd start falling behind if you stopped now.
    public static func catchUpTime(consumed: Double, goal: Double, on key: DayKey, hours: ActiveHours, clock: DayClock) -> Date {
        let window = hours.window(on: key, clock: clock)
        let span = window.sleep.timeIntervalSince(window.wake)
        guard goal > 0 else { return window.sleep }
        let fraction = min(max(consumed / goal, 0), 1)
        return window.wake.addingTimeInterval(span * fraction)
    }
}
