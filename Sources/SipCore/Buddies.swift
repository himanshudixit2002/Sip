import Foundation

/// What a buddy shares: today's progress and a few headline numbers. Each
/// person writes their own card into a shared folder (iCloud Drive) and reads
/// everyone else's; there is no server.
public struct BuddyCard: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var consumedML: Double
    public var goalML: Double
    public var percent: Int
    public var streak: Int
    public var level: Int
    public var levelTitle: String
    public var unit: VolumeUnit
    public var updated: Date

    public init(id: UUID, name: String, consumedML: Double, goalML: Double, percent: Int, streak: Int, level: Int,
                levelTitle: String, unit: VolumeUnit, updated: Date) {
        self.id = id
        self.name = name
        self.consumedML = consumedML
        self.goalML = goalML
        self.percent = percent
        self.streak = streak
        self.level = level
        self.levelTitle = levelTitle
        self.unit = unit
        self.updated = updated
    }
}

/// A friendly nudge from one buddy to another, dropped into the shared folder
/// and deleted by the recipient once shown.
public struct BuddyPoke: Codable, Equatable, Sendable {
    public var id: UUID
    public var from: String
    public var fromID: UUID
    public var to: UUID
    public var message: String
    public var sent: Date

    public init(id: UUID = UUID(), from: String, fromID: UUID, to: UUID, message: String, sent: Date) {
        self.id = id
        self.from = from
        self.fromID = fromID
        self.to = to
        self.message = message
        self.sent = sent
    }
}

public enum Buddies {
    /// "card-<uuid>.json".
    public static func cardFileName(id: UUID) -> String { "card-\(id.uuidString).json" }

    /// "poke-<to>-<id>.json": the recipient comes first so they can find
    /// theirs by name alone.
    public static func pokeFileName(to: UUID, id: UUID) -> String { "poke-\(to.uuidString)-\(id.uuidString).json" }

    /// Cards updated within `maxAge` of `now`, highest percent first (then by
    /// name). Older cards belong to someone who stopped sharing.
    public static func fresh(_ cards: [BuddyCard], now: Date, maxAge: TimeInterval = 36 * 3600) -> [BuddyCard] {
        cards.filter { now.timeIntervalSince($0.updated) <= maxAge }
            .sorted { $0.percent != $1.percent ? $0.percent > $1.percent : $0.name < $1.name }
    }

    /// Every readable card in `folder`, sorted by name. Unreadable files are
    /// skipped: a half-synced file shouldn't hide everyone else.
    public static func readCards(folder: URL) -> [BuddyCard] {
        files(in: folder, prefix: "card-")
            .compactMap { url in (try? Data(contentsOf: url)).flatMap { try? decoder.decode(BuddyCard.self, from: $0) } }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id.uuidString < $1.id.uuidString }
    }

    /// Pokes addressed to `id`, oldest first, with their files so they can be
    /// deleted once shown.
    public static func readPokes(folder: URL, for id: UUID) -> [(BuddyPoke, URL)] {
        files(in: folder, prefix: "poke-\(id.uuidString)-")
            .compactMap { url -> (BuddyPoke, URL)? in
                guard let data = try? Data(contentsOf: url),
                      let poke = try? decoder.decode(BuddyPoke.self, from: data), poke.to == id else { return nil }
                return (poke, url)
            }
            .sorted { $0.0.sent < $1.0.sent }
    }

    /// Writes (or replaces) this person's card. Returns where it went.
    @discardableResult
    public static func write(_ card: BuddyCard, to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(cardFileName(id: card.id))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(card).write(to: url, options: .atomic)
        return url
    }

    /// Drops a poke into the shared folder. Returns where it went.
    @discardableResult
    public static func send(_ poke: BuddyPoke, to folder: URL) throws -> URL {
        let url = folder.appendingPathComponent(pokeFileName(to: poke.to, id: poke.id))
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try encoder.encode(poke).write(to: url, options: .atomic)
        return url
    }

    private static func files(in folder: URL, prefix: String) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return urls.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
