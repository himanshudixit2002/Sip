import Foundation

public struct ReminderConfig: Equatable, Sendable {
    public var enabled: Bool
    public var intervalMinutes: Int
    /// Only remind when you'd otherwise fall behind, and stop once the goal is met.
    public var smart: Bool
    public var hours: ActiveHours
    public var snoozedUntil: Date?
    /// When the last reminder was shown: the next one is an interval after
    /// whichever is later, your last drink or the last reminder.
    public var lastReminder: Date?

    public init(enabled: Bool = true, intervalMinutes: Int = 60, smart: Bool = true,
                hours: ActiveHours = ActiveHours(), snoozedUntil: Date? = nil, lastReminder: Date? = nil) {
        self.enabled = enabled
        self.intervalMinutes = intervalMinutes
        self.smart = smart
        self.hours = hours
        self.snoozedUntil = snoozedUntil
        self.lastReminder = lastReminder
    }
}

public enum ReminderPlanner {
    /// How long after waking the first reminder of a fresh day may arrive.
    public static let morningGrace: TimeInterval = 15 * 60
    /// Never fire sooner than this after planning, so a relaunch doesn't
    /// immediately ping.
    public static let minimumLead: TimeInterval = 60

    /// When the next reminder should fire, or nil if none should.
    ///
    /// - The base time is your last drink today plus the interval (or wake time
    ///   plus the interval if you haven't had one).
    /// - In smart mode it's pushed out to when you'd actually fall behind, and
    ///   skipped to tomorrow morning once the goal is met.
    /// - It's always moved inside your waking hours.
    public static func nextFire(
        now: Date,
        lastSip: Date?,
        consumed: Double,
        goal: Double,
        config: ReminderConfig,
        clock: DayClock
    ) -> Date? {
        guard config.enabled, config.intervalMinutes > 0 else { return nil }
        let interval = TimeInterval(config.intervalMinutes * 60)
        let today = clock.key(for: now)
        let window = config.hours.window(on: today, clock: clock)
        let tomorrowMorning = config.hours.window(on: today.next, clock: clock).wake.addingTimeInterval(morningGrace)

        if config.smart, goal > 0, consumed >= goal - 0.5 { return tomorrowMorning }

        let start = clock.start(of: today)
        let anchors = [lastSip, config.lastReminder].compactMap { $0 }.filter { $0 >= start }
        var candidate = (anchors.max() ?? window.wake).addingTimeInterval(interval)

        if config.smart {
            // You only count as behind once the ideal line passes what you've
            // drunk plus the on-track tolerance; before then a reminder would
            // be nagging.
            let behindAt = Pace.catchUpTime(consumed: consumed + Pace.tolerance(goal: goal), goal: goal,
                                            on: today, hours: config.hours, clock: clock)
            candidate = max(candidate, behindAt)
        }

        if let snoozed = config.snoozedUntil, snoozed > candidate { candidate = snoozed }
        candidate = max(candidate, now.addingTimeInterval(minimumLead))

        if candidate < window.wake { candidate = window.wake.addingTimeInterval(morningGrace) }
        if candidate >= window.sleep { candidate = tomorrowMorning }
        return candidate
    }
}
