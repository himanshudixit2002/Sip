import Foundation

/// What the system widget shows. The widget runs in a sandbox and can't read
/// the history or settings, so the app writes this small, already-formatted
/// summary whenever today's numbers change.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public struct Cup: Codable, Equatable, Sendable {
        public var name: String
        public var label: String
        public var symbol: String
        public init(name: String, label: String, symbol: String) {
            self.name = name
            self.label = label
            self.symbol = symbol
        }
    }

    public struct Day: Codable, Equatable, Sendable {
        public var letter: String
        public var progress: Double
        public var met: Bool
        public var isToday: Bool
        public init(letter: String, progress: Double, met: Bool, isToday: Bool) {
            self.letter = letter
            self.progress = progress
            self.met = met
            self.isToday = isToday
        }
    }

    public var progress: Double
    public var consumedText: String
    public var goalText: String
    public var streak: Int
    public var level: Int
    public var levelTitle: String
    public var challenge: String?
    public var challengeDone: Bool
    public var cups: [Cup]
    public var week: [Day]
    /// Liquid colours, top to bottom, as 0xRRGGBB.
    public var colors: [Int]
    public var updated: Date

    public init(progress: Double, consumedText: String, goalText: String, streak: Int, level: Int, levelTitle: String,
                challenge: String?, challengeDone: Bool, cups: [Cup], week: [Day], colors: [Int], updated: Date) {
        self.progress = progress
        self.consumedText = consumedText
        self.goalText = goalText
        self.streak = streak
        self.level = level
        self.levelTitle = levelTitle
        self.challenge = challenge
        self.challengeDone = challengeDone
        self.cups = cups
        self.week = week
        self.colors = colors
        self.updated = updated
    }

    public static let fileName = "widget.json"

    /// `~/Library/Application Support/Sip/widget.json`, from the real home
    /// folder, so the sandboxed widget finds the same file.
    public static var fileURL: URL { SipPaths.localFolder.appendingPathComponent(fileName) }

    public static func load() -> WidgetSnapshot? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    public func write() throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try FileManager.default.createDirectory(at: Self.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(self).write(to: Self.fileURL, options: .atomic)
    }

    public static let sample = WidgetSnapshot(
        progress: 0.62, consumedText: "1.55 L", goalText: "2.5 L", streak: 12, level: 9, levelTitle: "Stream",
        challenge: "Morning Litre", challengeDone: false,
        cups: [Cup(name: "Sip", label: "+150", symbol: "drop.fill"), Cup(name: "Glass", label: "+250", symbol: "cup.and.saucer.fill"),
               Cup(name: "Bottle", label: "+500", symbol: "waterbottle.fill")],
        week: ["M", "T", "W", "T", "F", "S", "S"].enumerated().map { Day(letter: $1, progress: [1.1, 0.9, 1.05, 1.2, 1, 1.15, 0.62][$0], met: $0 != 1 && $0 != 6, isToday: $0 == 6) },
        colors: [0x8FE3FF, 0x2E9BFF, 0x0B3D91], updated: Date())
}
