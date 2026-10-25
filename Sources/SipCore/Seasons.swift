import Foundation

/// Seasonal decorations for the bottle and widget.
public enum SeasonPack: String, CaseIterable, Sendable {
    case diwali
    case holi
    case monsoon
    case winter
    case christmas
    case newYear
}

public enum Seasons {
    /// Diwali moves with the lunar calendar, so its dates are listed. The pack
    /// shows for two days either side.
    static let diwali: [DayKey] = [
        DayKey(year: 2025, month: 10, day: 21), DayKey(year: 2026, month: 11, day: 8),
        DayKey(year: 2027, month: 10, day: 29), DayKey(year: 2028, month: 10, day: 17),
        DayKey(year: 2029, month: 11, day: 5), DayKey(year: 2030, month: 10, day: 26),
    ]

    /// Holi, shown on the day before (Holika Dahan) and the day itself.
    static let holi: [DayKey] = [
        DayKey(year: 2026, month: 3, day: 4), DayKey(year: 2027, month: 3, day: 22),
        DayKey(year: 2028, month: 3, day: 11), DayKey(year: 2029, month: 3, day: 1),
        DayKey(year: 2030, month: 3, day: 20),
    ]

    /// The pack for the calendar date of `date` in `calendar`, if any.
    /// Festivals win over seasons: Diwali, Holi, New Year (31 Dec – 1 Jan) and
    /// Christmas (20–26 Dec); then monsoon (10 Jun – 30 Sep) and winter
    /// (1 Dec to the end of February).
    public static func active(on date: Date, calendar: Calendar) -> SeasonPack? {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = c.year, let month = c.month, let day = c.day else { return nil }
        let key = DayKey(year: year, month: month, day: day)

        if diwali.contains(where: { abs($0.days(to: key)) <= 2 }) { return .diwali }
        if holi.contains(where: { key == $0 || key == $0.previous }) { return .holi }
        if (month == 12 && day == 31) || (month == 1 && day == 1) { return .newYear }
        if month == 12, (20...26).contains(day) { return .christmas }
        if (month == 6 && day >= 10) || (7...9).contains(month) { return .monsoon }
        if month == 12 || month == 1 || month == 2 { return .winter }
        return nil
    }
}

/// How the glass looks with today's weather: frosted when cold, beaded with
/// rain, misty when humid, shimmering when hot. Every value is 0 when the
/// weather is unknown.
public struct GlassMood: Equatable, Sendable {
    /// 0 at 12 °C and above, rising to 1 at 0 °C.
    public var frost: Double
    /// Drizzle, rain, showers or thunder.
    public var rain: Bool
    /// 0 at 70% humidity, rising to 1 at 100%.
    public var humid: Double
    /// 0 at 30 °C, rising to 1 at 40 °C.
    public var heat: Double

    public init(frost: Double, rain: Bool, humid: Double, heat: Double) {
        self.frost = frost
        self.rain = rain
        self.humid = humid
        self.heat = heat
    }

    public static let neutral = GlassMood(frost: 0, rain: false, humid: 0, heat: 0)

    /// From an Open-Meteo style reading: temperature in °C, relative humidity
    /// in %, and a WMO weather code.
    public static func make(temperatureC: Double?, humidity: Double?, weatherCode: Int?) -> GlassMood {
        func ramp(_ value: Double, from start: Double, to end: Double) -> Double {
            min(max((value - start) / (end - start), 0), 1)
        }
        return GlassMood(frost: temperatureC.map { ramp($0, from: 12, to: 0) } ?? 0,
                         rain: weatherCode.map(WeatherKind.isWet) ?? false,
                         humid: humidity.map { ramp($0, from: 70, to: 100) } ?? 0,
                         heat: temperatureC.map { ramp($0, from: 30, to: 40) } ?? 0)
    }
}

/// The broad kind of weather behind a WMO code.
public enum WeatherKind: String, CaseIterable, Sendable {
    case clear
    case cloudy
    case fog
    case drizzle
    case rain
    case snow
    case storm

    /// Unknown codes count as cloudy, the least surprising guess.
    public init(wmoCode code: Int) {
        switch code {
        case 0, 1: self = .clear
        case 2, 3: self = .cloudy
        case 45, 48: self = .fog
        case 51...57: self = .drizzle
        case 61...67, 80...82: self = .rain
        case 71...77, 85, 86: self = .snow
        case 95...99: self = .storm
        default: self = .cloudy
        }
    }

    /// Codes that put drops on the glass: drizzle and rain (51–67), showers
    /// (80–82) and thunderstorms (95–99).
    public static func isWet(_ code: Int) -> Bool {
        (51...67).contains(code) || (80...82).contains(code) || (95...99).contains(code)
    }
}
