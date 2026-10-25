import Foundation

/// Everything Sip remembers about what you drank. This is the whole file on
/// disk; streaks, totals and charts are all derived from it.
public struct HydrationHistory: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Kept sorted by date.
    public private(set) var entries: [Entry]
    /// The goal that applied on each day, keyed by `DayKey.description`.
    /// Written the first time a day gets an entry and whenever the goal
    /// changes during that day, so a later change never rewrites the past.
    public var dayGoals: [String: Double]
    /// Entries deleted on this Mac. Kept so that when two copies of the file
    /// are merged (iCloud sync between Macs) a deletion isn't undone by the
    /// other copy still having the entry.
    public private(set) var deletedIDs: Set<UUID>

    public init(entries: [Entry] = [], dayGoals: [String: Double] = [:], deletedIDs: Set<UUID> = []) {
        self.version = HydrationHistory.currentVersion
        self.entries = entries.sorted { $0.date < $1.date }
        self.dayGoals = dayGoals
        self.deletedIDs = deletedIDs
    }

    private enum CodingKeys: String, CodingKey { case version, entries, dayGoals, deletedIDs }

    // Files written before sync existed have no `deletedIDs`.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        entries = try c.decode([Entry].self, forKey: .entries).sorted { $0.date < $1.date }
        dayGoals = try c.decodeIfPresent([String: Double].self, forKey: .dayGoals) ?? [:]
        deletedIDs = try c.decodeIfPresent(Set<UUID>.self, forKey: .deletedIDs) ?? []
    }

    /// Everything in either copy, minus anything either copy deleted. Day
    /// goals from `self` win where both have one.
    public func merged(with other: HydrationHistory) -> HydrationHistory {
        let deleted = deletedIDs.union(other.deletedIDs)
        var byID: [UUID: Entry] = [:]
        for entry in other.entries + entries where !deleted.contains(entry.id) { byID[entry.id] = entry }
        let goals = other.dayGoals.merging(dayGoals) { _, mine in mine }
        return HydrationHistory(entries: Array(byID.values), dayGoals: goals, deletedIDs: deleted)
    }

    public mutating func insert(_ entry: Entry) {
        let index = entries.firstIndex { $0.date > entry.date } ?? entries.endIndex
        entries.insert(entry, at: index)
    }

    @discardableResult
    public mutating func remove(id: UUID) -> Entry? {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return nil }
        deletedIDs.insert(id)
        return entries.remove(at: index)
    }

    public mutating func removeAll() {
        deletedIDs.formUnion(entries.map(\.id))
        entries.removeAll()
        dayGoals.removeAll()
    }

    /// The goal for `key`: the one recorded that day, else the most recent one
    /// recorded before it, else `fallback`.
    public func goal(for key: DayKey, fallback: Double) -> Double {
        if let exact = dayGoals[key.description] { return exact }
        let earlier = dayGoals
            .compactMap { pair -> (DayKey, Double)? in
                guard let k = DayKey(pair.key), k < key else { return nil }
                return (k, pair.value)
            }
            .max { $0.0 < $1.0 }
        return earlier?.1 ?? fallback
    }
}

/// One day, totalled.
public struct DaySummary: Equatable, Sendable, Identifiable {
    public var key: DayKey
    public var rawML: Double
    public var effectiveML: Double
    public var goalML: Double
    public var entryCount: Int
    public var byDrink: [DrinkKind: Double]

    public var id: DayKey { key }
    public var met: Bool { goalML > 0 && effectiveML >= goalML - 0.5 }
    public var progress: Double { goalML > 0 ? effectiveML / goalML : 0 }

    public static func empty(_ key: DayKey, goal: Double) -> DaySummary {
        DaySummary(key: key, rawML: 0, effectiveML: 0, goalML: goal, entryCount: 0, byDrink: [:])
    }
}

public enum HistoryMath {
    /// Groups entries into days. Only days with at least one entry appear.
    public static func summaries(
        _ history: HydrationHistory,
        clock: DayClock,
        factors: HydrationFactors,
        fallbackGoal: Double
    ) -> [DayKey: DaySummary] {
        var result: [DayKey: DaySummary] = [:]
        for entry in history.entries {
            let key = clock.key(for: entry.date)
            var summary = result[key]
                ?? .empty(key, goal: history.goal(for: key, fallback: fallbackGoal))
            summary.rawML += entry.amountML
            summary.effectiveML += entry.effectiveML(factors)
            summary.entryCount += 1
            summary.byDrink[entry.drink, default: 0] += entry.amountML
            result[key] = summary
        }
        return result
    }

    public static func entries(on key: DayKey, in history: HydrationHistory, clock: DayClock) -> [Entry] {
        Array(entries(from: clock.start(of: key), to: clock.end(of: key), in: history))
    }

    /// Entries from `start` up to but not including `end`. History is kept
    /// sorted, so this is a binary search rather than a scan of every entry.
    public static func entries(from start: Date, to end: Date, in history: HydrationHistory) -> ArraySlice<Entry> {
        let all = history.entries
        guard start < end else { return all[all.startIndex..<all.startIndex] }
        let lower = firstIndex(in: all) { $0.date >= start }
        let upper = firstIndex(in: all) { $0.date >= end }
        return all[lower..<max(lower, upper)]
    }

    /// Entries grouped by drinking day in a single pass, each day in time
    /// order. Features that look at every day call this once instead of
    /// filtering the whole history per day.
    public static func entriesByDay<S: Sequence>(_ entries: S, clock: DayClock) -> [DayKey: [Entry]] where S.Element == Entry {
        var result: [DayKey: [Entry]] = [:]
        for entry in entries { result[clock.key(for: entry.date), default: []].append(entry) }
        for (key, list) in result where zip(list, list.dropFirst()).contains(where: { $0.date > $1.date }) {
            result[key] = list.sorted { $0.date < $1.date }
        }
        return result
    }

    /// First index whose entry satisfies `isAtOrAfter`, which must be false
    /// then true along the sorted array.
    private static func firstIndex(in entries: [Entry], where isAtOrAfter: (Entry) -> Bool) -> Int {
        var low = entries.startIndex
        var high = entries.endIndex
        while low < high {
            let mid = (low + high) / 2
            if isAtOrAfter(entries[mid]) { high = mid } else { low = mid + 1 }
        }
        return low
    }
}

// MARK: - Persistence

public enum HistoryFile {
    public enum LoadError: Error, LocalizedError {
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .newerVersion(let v):
                return "This history file was written by a newer version of Sip (format \(v))."
            }
        }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// A missing file is an empty history, not an error.
    public static func load(from url: URL) throws -> HydrationHistory {
        guard FileManager.default.fileExists(atPath: url.path) else { return HydrationHistory() }
        let data = try Data(contentsOf: url)
        let history = try decoder.decode(HydrationHistory.self, from: data)
        if history.version > HydrationHistory.currentVersion {
            throw LoadError.newerVersion(history.version)
        }
        return history
    }

    /// Written to a temporary file and swapped into place, so a crash halfway
    /// through can never leave a truncated history behind.
    public static func save(_ history: HydrationHistory, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(history)
        try data.write(to: url, options: .atomic)
    }
}

// MARK: - CSV

public enum HistoryCSV {
    public static let header = "date,amount_ml,drink"

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    public static func export(_ history: HydrationHistory) -> String {
        var lines = [header]
        for entry in history.entries {
            lines.append("\(iso.string(from: entry.date)),\(Int(entry.amountML.rounded())),\(entry.drink.rawValue)")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Accepts the export format. Unknown drink names become water; rows that
    /// can't be read are skipped and counted.
    public static func parse(_ text: String) -> (entries: [Entry], skipped: Int) {
        var entries: [Entry] = []
        var skipped = 0
        for (index, rawLine) in text.split(whereSeparator: \.isNewline).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || (index == 0 && line.lowercased().hasPrefix("date")) { continue }
            let fields = line.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard fields.count >= 2,
                  let date = iso.date(from: fields[0]),
                  let amount = Double(fields[1]), amount > 0 else {
                skipped += 1
                continue
            }
            let drink = fields.count >= 3 ? (DrinkKind(rawValue: fields[2]) ?? .water) : .water
            entries.append(Entry(date: date, amountML: amount, drink: drink))
        }
        return (entries, skipped)
    }
}
