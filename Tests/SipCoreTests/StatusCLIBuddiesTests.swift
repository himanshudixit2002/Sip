import Foundation
import Testing
@testable import SipCore

private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("sip-test-\(UUID().uuidString)", isDirectory: true)
}

/// A whole-second date, since ISO 8601 files keep seconds only.
private let noon = Date(timeIntervalSince1970: 1_791_288_000)

@Suite("Status")
struct StatusTests {
    @Test func sentence() {
        let status = SipStatus(consumedML: 2100, goalML: 4000, unit: .milliliters, streak: 6, bestStreak: 10, level: 9,
                               levelTitle: "Stream", updated: noon)
        #expect(status.percent == 53)
        #expect(status.sentence() == "2.1 L of 4 L (53%) · 6-day streak · level 9 Stream")
        let fresh = SipStatus(consumedML: 500, goalML: 2000, unit: .milliliters, streak: 0, bestStreak: 0, level: 0,
                              levelTitle: "", updated: noon)
        #expect(fresh.sentence() == "500 ml of 2 L (25%)")
    }

    @Test func writeAndLoad() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("status.json")
        let status = SipStatus(consumedML: 1800, goalML: 2500, unit: .fluidOunces, streak: 3, bestStreak: 12, level: 4,
                               levelTitle: "Puddle", caffeineNowMG: 85.5, challengeTitle: "Morning Boost",
                               challengeDone: true, nextReminder: noon.addingTimeInterval(3600), updated: noon)
        try status.write(to: url)
        #expect(SipStatus.load(from: url) == status)
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("\"updated\" : \"2026-"))
        #expect(status.json().contains("\"levelTitle\" : \"Puddle\""))
        #expect(SipStatus.load(from: folder.appendingPathComponent("missing.json")) == nil)
        try Data("not json".utf8).write(to: url)
        #expect(SipStatus.load(from: url) == nil)
        #expect(SipPaths.statusFile.path.hasSuffix("Library/Application Support/Sip/status.json"))
    }
}

@Suite("Command line")
struct CLITests {
    private func parse(_ args: String...) -> Result<CLICommand, CLIError> { CLICommand.parse(args) }

    @Test func commands() {
        #expect(parse() == .success(.status(json: false)))
        #expect(parse("330", "tea") == .success(.log("330 tea")))
        #expect(parse(".5l") == .success(.log(".5l")))
        #expect(parse("log", "two", "glasses") == .success(.log("two glasses")))
        #expect(parse("status") == .success(.status(json: false)))
        #expect(parse("status", "--json") == .success(.status(json: true)))
        #expect(parse("--json") == .success(.status(json: true)))
        #expect(parse("UNDO") == .success(.undo))
        #expect(parse("refill") == .success(.refill))
        #expect(parse("peek") == .success(.peek))
        #expect(parse("quicklog") == .success(.quickLog))
        #expect(parse("open", "Settings") == .success(.open("settings")))
        #expect(parse("insights") == .success(.open("insights")))
        #expect(parse("-h") == .success(.help))
        #expect(parse("--version") == .success(.version))
    }

    @Test func mistakesGetHelpfulErrors() {
        #expect(parse("log") == .failure(.missingText))
        #expect(parse("open") == .failure(.missingTarget))
        #expect(parse("open", "garage") == .failure(.unknownTarget("garage")))
        #expect(parse("undo", "now") == .failure(.unexpectedArgument(command: "undo", argument: "now")))
        #expect(parse("status", "--loud") == .failure(.unknownOption("--loud")))
        #expect(parse("--frobnicate") == .failure(.unknownOption("--frobnicate")))
        guard case .failure(let error) = parse("dance") else {
            Issue.record("expected an error")
            return
        }
        #expect(error == .unknownCommand("dance"))
        #expect(error.description.contains("sip help"))
        #expect(error.description.contains("sip log dance"))
    }

    @Test func urls() {
        let log = CLICommand.log("330 tea & more+1")
        #expect(log.url?.absoluteString == "sip://log?text=330%20tea%20%26%20more%2B1")
        let decoded = log.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?.queryItems?.first?.value
        #expect(decoded == "330 tea & more+1")
        #expect(CLICommand.log("½ glass").url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }?
            .queryItems?.first?.value == "½ glass")
        #expect(CLICommand.undo.url?.absoluteString == "sip://undo")
        #expect(CLICommand.refill.url?.absoluteString == "sip://refill")
        #expect(CLICommand.peek.url?.absoluteString == "sip://peek")
        #expect(CLICommand.quickLog.url?.absoluteString == "sip://quicklog")
        #expect(CLICommand.open("settings").url?.absoluteString == "sip://settings")
        #expect(CLICommand.open("insights").url?.absoluteString == "sip://insights")
        #expect(CLICommand.open("garage").url == nil)
        #expect(CLICommand.status(json: true).url == nil)
        #expect(CLICommand.help.url == nil && CLICommand.version.url == nil)
    }

    @Test func helpMentionsEveryCommand() {
        for word in ["sip log", "sip status", "sip undo", "sip refill", "sip peek", "sip quicklog", "sip open settings",
                     "sip open insights", "sip help", "sip version"] {
            #expect(CLICommand.helpText.contains(word))
        }
    }
}

@Suite("Buddies")
struct BuddyTests {
    private let alice = UUID()
    private let bob = UUID()

    private func card(_ id: UUID, _ name: String, percent: Int, updated: Date) -> BuddyCard {
        BuddyCard(id: id, name: name, consumedML: Double(percent) * 20, goalML: 2000, percent: percent, streak: 3,
                  level: 5, levelTitle: "Trickle", unit: .milliliters, updated: updated)
    }

    @Test func fileNames() {
        let a = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let b = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!
        #expect(Buddies.cardFileName(id: a) == "card-11111111-2222-3333-4444-555555555555.json")
        #expect(Buddies.pokeFileName(to: a, id: b) == "poke-11111111-2222-3333-4444-555555555555-AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE.json")
    }

    @Test func freshCardsSortedByProgress() {
        let cards = [card(alice, "Alice", percent: 40, updated: noon.addingTimeInterval(-3600)),
                     card(bob, "Bob", percent: 80, updated: noon.addingTimeInterval(-7200)),
                     card(UUID(), "Cara", percent: 99, updated: noon.addingTimeInterval(-40 * 3600)),
                     card(UUID(), "Dev", percent: 80, updated: noon)]
        #expect(Buddies.fresh(cards, now: noon).map(\.name) == ["Bob", "Dev", "Alice"])
        #expect(Buddies.fresh(cards, now: noon, maxAge: 5000).map(\.name) == ["Dev", "Alice"])
    }

    @Test func cardsAndPokesThroughAFolder() throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Buddies.write(card(alice, "Alice", percent: 40, updated: noon), to: folder)
        try Buddies.write(card(bob, "Bob", percent: 70, updated: noon), to: folder)
        try Data("garbage".utf8).write(to: folder.appendingPathComponent("card-broken.json"))
        #expect(Buddies.readCards(folder: folder).map(\.name) == ["Alice", "Bob"])
        #expect(Buddies.readCards(folder: folder).first == card(alice, "Alice", percent: 40, updated: noon))

        let later = BuddyPoke(from: "Bob", fromID: bob, to: alice, message: "Drink up!", sent: noon.addingTimeInterval(60))
        let first = BuddyPoke(from: "Bob", fromID: bob, to: alice, message: "Hey", sent: noon)
        try Buddies.send(later, to: folder)
        let url = try Buddies.send(first, to: folder)
        try Buddies.send(BuddyPoke(from: "Alice", fromID: alice, to: bob, message: "You too", sent: noon), to: folder)
        let pokes = Buddies.readPokes(folder: folder, for: alice)
        #expect(pokes.map { $0.0 } == [first, later])
        #expect(pokes.first?.1.lastPathComponent == url.lastPathComponent)
        #expect(Buddies.readPokes(folder: folder, for: bob).count == 1)
        #expect(Buddies.readCards(folder: folder.appendingPathComponent("nowhere")).isEmpty)
    }
}
