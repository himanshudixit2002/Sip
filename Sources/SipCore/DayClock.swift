import Foundation

/// A calendar date with no time or zone attached. Days in Sip are "drinking
/// days", which start at a configurable hour rather than at midnight, so a
/// glass at 01:30 still belongs to the evening before.
public struct DayKey: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses `yyyy-MM-dd`.
    public init?(_ string: String) {
        let parts = string.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func < (lhs: DayKey, rhs: DayKey) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    /// Date arithmetic on a key is pure calendar arithmetic, so it runs in a
    /// fixed UTC Gregorian calendar where no day is ever 23 or 25 hours long.
    private static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private var utcNoon: Date {
        DayKey.utc.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    public func adding(days: Int) -> DayKey {
        let date = DayKey.utc.date(byAdding: .day, value: days, to: utcNoon)!
        let c = DayKey.utc.dateComponents([.year, .month, .day], from: date)
        return DayKey(year: c.year!, month: c.month!, day: c.day!)
    }

    public var next: DayKey { adding(days: 1) }
    public var previous: DayKey { adding(days: -1) }

    /// Whole days from `self` to `other`; positive when `other` is later.
    public func days(to other: DayKey) -> Int {
        DayKey.utc.dateComponents([.day], from: utcNoon, to: other.utcNoon).day ?? 0
    }

    /// 1 = Sunday … 7 = Saturday, matching `Calendar.component(.weekday)`.
    public var weekday: Int { DayKey.utc.component(.weekday, from: utcNoon) }

    /// The weekday's name in `calendar`'s language: "M" when `short`, else
    /// "Mon". Chart labels use the one-letter form where space is tight.
    public func weekdaySymbol(short: Bool, calendar: Calendar = .current) -> String {
        let symbols = short ? calendar.veryShortWeekdaySymbols : calendar.shortWeekdaySymbols
        let index = weekday - 1
        return symbols.indices.contains(index) ? symbols[index] : ""
    }
}

/// Maps instants to drinking days and back.
public struct DayClock: Sendable {
    /// Hour of the day (0–23) at which a new drinking day begins.
    public var dayStartHour: Int
    public var calendar: Calendar

    public init(dayStartHour: Int = 4, calendar: Calendar = .current) {
        self.dayStartHour = min(max(dayStartHour, 0), 23)
        self.calendar = calendar
    }

    /// Hours before `dayStartHour` are counted toward the previous day. This
    /// reads the wall-clock hour rather than subtracting a fixed interval, so a
    /// daylight-saving change can't push an entry into the wrong day.
    public func key(for date: Date) -> DayKey {
        let c = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        let key = DayKey(year: c.year!, month: c.month!, day: c.day!)
        return (c.hour ?? 0) < dayStartHour ? key.previous : key
    }

    /// The instant the drinking day `key` begins.
    public func start(of key: DayKey) -> Date {
        let components = DateComponents(year: key.year, month: key.month, day: key.day, hour: dayStartHour)
        return calendar.date(from: components)!
    }

    public func end(of key: DayKey) -> Date { start(of: key.next) }

    /// The next day boundary strictly after `date`.
    public func nextBoundary(after date: Date) -> Date {
        end(of: key(for: date))
    }

    /// `minutes` past midnight on the calendar date of `key`. Used for wake and
    /// sleep times, which are wall-clock times rather than offsets from the
    /// day boundary.
    public func time(_ minutes: Int, on key: DayKey) -> Date {
        let midnight = calendar.date(from: DateComponents(year: key.year, month: key.month, day: key.day))!
        return calendar.date(byAdding: .minute, value: minutes, to: midnight)!
    }
}
