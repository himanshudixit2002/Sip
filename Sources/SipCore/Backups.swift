import Foundation

public struct BackupInfo: Equatable, Sendable {
    public var day: DayKey
    public var url: URL
    /// Bytes on disk.
    public var size: Int
    /// Nil when the file can't be read as a history.
    public var entryCount: Int?
}

/// Rolling daily copies of history.json: the last week of days, then one per
/// week for a month before that. Enough to undo a bad import or sync without
/// keeping every day forever.
public enum Backups {
    private static let prefix = "history-"
    private static let suffix = ".json"

    /// "history-2026-10-06.json".
    public static func fileName(for day: DayKey) -> String { "\(prefix)\(day)\(suffix)" }

    /// The day in a backup's file name, or nil for any other file.
    public static func day(fromFileName name: String) -> DayKey? {
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }
        let middle = String(name.dropFirst(prefix.count).dropLast(suffix.count))
        guard let day = DayKey(middle), (1...12).contains(day.month), (1...31).contains(day.day),
              fileName(for: day) == name else { return nil }
        return day
    }

    /// Which backups to keep: the newest `daily` of them, then the newest one
    /// in each of the `weekly` ISO weeks before those. Days after `today`
    /// (a clock that was wrong for a while) are always kept and don't use up
    /// a place.
    public static func toKeep(existing: [DayKey], today: DayKey, daily: Int = 7, weekly: Int = 4) -> Set<DayKey> {
        let unique = Set(existing)
        var keep = unique.filter { $0 > today }
        let past = unique.filter { $0 <= today }.sorted(by: >)
        let recent = past.prefix(max(daily, 0))
        keep.formUnion(recent)
        var weeks = Set(recent.map(isoWeek))
        var weeklyKept = 0
        for day in past.dropFirst(recent.count) where weeklyKept < weekly {
            let week = isoWeek(day)
            if weeks.contains(week) { continue }
            weeks.insert(week)
            keep.insert(day)
            weeklyKept += 1
        }
        return keep
    }

    /// Copies history into `folder` if today has no backup yet, then deletes
    /// backups that `toKeep` drops. Returns whether a copy was made. Files in
    /// the folder that aren't backups are left alone.
    @discardableResult
    public static func run(historyURL: URL, folder: URL, today: DayKey) throws -> Bool {
        let fm = FileManager.default
        var copied = false
        if fm.fileExists(atPath: historyURL.path) {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(fileName(for: today))
            if !fm.fileExists(atPath: target.path) {
                try fm.copyItem(at: historyURL, to: target)
                copied = true
            }
        }
        guard fm.fileExists(atPath: folder.path) else { return copied }
        var byDay: [DayKey: URL] = [:]
        for url in try fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) {
            if let day = Self.day(fromFileName: url.lastPathComponent) { byDay[day] = url }
        }
        let keep = toKeep(existing: Array(byDay.keys), today: today)
        for (day, url) in byDay where !keep.contains(day) {
            try? fm.removeItem(at: url)
        }
        return copied
    }

    /// Every backup in `folder`, newest first.
    public static func list(folder: URL) -> [BackupInfo] {
        let fm = FileManager.default
        guard let urls = try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else {
            return []
        }
        return urls.compactMap { url -> BackupInfo? in
            guard let day = Self.day(fromFileName: url.lastPathComponent) else { return nil }
            let size = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            let count = (try? HistoryFile.load(from: url))?.entries.count
            return BackupInfo(day: day, url: url, size: size, entryCount: count)
        }
        .sorted { $0.day > $1.day }
    }

    private static let isoCalendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }()

    /// Year-for-week × 100 + ISO week number.
    static func isoWeek(_ day: DayKey) -> Int {
        guard let date = isoCalendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12))
        else { return 0 }
        let c = isoCalendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return (c.yearForWeekOfYear ?? 0) * 100 + (c.weekOfYear ?? 0)
    }
}
