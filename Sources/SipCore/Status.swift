import Foundation

/// Today at a glance, written by the app to `SipPaths.statusFile` whenever it
/// changes so the `sip` command line tool can answer without the app's help.
public struct SipStatus: Codable, Equatable, Sendable {
    public var consumedML: Double
    public var goalML: Double
    public var unit: VolumeUnit
    /// Share of the goal, rounded to a whole percent.
    public var percent: Int
    public var streak: Int
    public var bestStreak: Int
    public var level: Int
    public var levelTitle: String
    /// Nil when caffeine tracking is off.
    public var caffeineNowMG: Double?
    public var challengeTitle: String?
    public var challengeDone: Bool
    public var nextReminder: Date?
    public var updated: Date

    /// `percent` is worked out from the two amounts.
    public init(consumedML: Double, goalML: Double, unit: VolumeUnit, streak: Int, bestStreak: Int, level: Int,
                levelTitle: String, caffeineNowMG: Double? = nil, challengeTitle: String? = nil,
                challengeDone: Bool = false, nextReminder: Date? = nil, updated: Date) {
        self.consumedML = consumedML
        self.goalML = goalML
        self.unit = unit
        self.percent = goalML > 0 ? Int((consumedML / goalML * 100).rounded()) : 0
        self.streak = streak
        self.bestStreak = bestStreak
        self.level = level
        self.levelTitle = levelTitle
        self.caffeineNowMG = caffeineNowMG
        self.challengeTitle = challengeTitle
        self.challengeDone = challengeDone
        self.nextReminder = nextReminder
        self.updated = updated
    }

    /// "2.1 L of 4 L (53%) · 6-day streak · level 9 Stream". Parts with
    /// nothing to say (no streak, no level) are left out.
    public func sentence() -> String {
        var parts = ["\(Volume.formatCompact(consumedML, unit)) of \(Volume.formatCompact(goalML, unit)) (\(percent)%)"]
        if streak > 0 { parts.append("\(streak)-day streak") }
        if level > 0 { parts.append("level \(level) \(levelTitle)") }
        return parts.joined(separator: " · ")
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

    /// Nil if the file is missing or unreadable: the app may not have run yet.
    public static func load(from url: URL) -> SipStatus? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SipStatus.self, from: data)
    }

    /// Written atomically, so the tool never reads half a file. Dates are
    /// ISO 8601 to the second.
    public func write(to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try SipStatus.encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The JSON the tool prints for `sip status --json`.
    public func json() -> String {
        (try? SipStatus.encoder.encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
    }
}
