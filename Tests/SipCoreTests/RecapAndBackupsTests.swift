import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()
private let clock = DayClock(dayStartHour: 4, calendar: calendar)

private func at(_ m: Int, _ d: Int, _ h: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: m, day: d, hour: h))!
}

private func key(_ s: String) -> DayKey { DayKey(s)! }

/// September: 1st–3rd 1 L water + 1.2 L tea (met), 4th 500 ml (missed),
/// 5th–6th 2.1 L water (met). October 1st: 3 L.
private let history: HydrationHistory = {
    var entries: [Entry] = []
    for d in 1...3 {
        entries.append(Entry(date: at(9, d, 9), amountML: 1000))
        entries.append(Entry(date: at(9, d, 14), amountML: 1200, drink: .tea))
    }
    entries.append(Entry(date: at(9, 4, 9), amountML: 500))
    for d in 5...6 {
        entries.append(Entry(date: at(9, d, 9), amountML: 1000))
        entries.append(Entry(date: at(9, d, 14), amountML: 1100))
    }
    entries.append(Entry(date: at(10, 1, 10), amountML: 3000))
    return HydrationHistory(entries: entries)
}()
private let summaries = HistoryMath.summaries(history, clock: clock, factors: HydrationFactors(), fallbackGoal: 2000)

@Suite("Recap")
struct RecapTests {
    @Test func monthNumbers() {
        let r = Recap.month(containing: key("2026-09-15"), history: history, summaries: summaries, clock: clock, bottleML: 750)
        #expect(r.title == "September 2026")
        #expect(r.from == key("2026-09-01") && r.to == key("2026-09-30"))
        #expect(r.totalML == 11_300)
        #expect(r.daysLogged == 6 && r.daysMet == 5 && r.bestRun == 3)
        #expect(r.favoriteDrink == .water)
        #expect(abs(r.favoriteDrinkShare - 7700.0 / 11_300) < 1e-9)
        #expect(r.peakHour == 14)
        #expect(abs(r.averageML - 10_940.0 / 6) < 1e-6)
        #expect(r.bestDay == RecapDay(key: key("2026-09-05"), effectiveML: 2100))
        #expect(abs(r.bathtubs - 11_300.0 / 150_000) < 1e-12)
        #expect(r.bottles == 15)
    }

    @Test func yearAndPreviousMonth() {
        let year = Recap.year(2026, history: history, summaries: summaries, clock: clock, bottleML: 1000)
        #expect(year.title == "2026" && year.totalML == 14_300 && year.daysLogged == 7 && year.daysMet == 6)
        #expect(year.bestRun == 3 && year.bottles == 14)
        let previous = Recap.previousMonth(of: key("2026-10-06"), history: history, summaries: summaries, clock: clock,
                                           bottleML: 750)
        #expect(previous == Recap.month(containing: key("2026-09-30"), history: history, summaries: summaries,
                                        clock: clock, bottleML: 750))
        let january = Recap.previousMonth(of: key("2027-01-03"), history: history, summaries: summaries, clock: clock,
                                          bottleML: 750)
        #expect(january.title == "December 2026" && january.to == key("2026-12-31"))
    }

    @Test func anEmptyRangeIsAllZeros() {
        let r = Recap.month(containing: key("2026-02-10"), history: history, summaries: summaries, clock: clock, bottleML: 750)
        #expect(r.to == key("2026-02-28"))
        #expect(r.totalML == 0 && r.daysLogged == 0 && r.bestRun == 0 && r.averageML == 0 && r.bottles == 0)
        #expect(r.favoriteDrink == nil && r.peakHour == nil && r.bestDay == nil)
    }
}

@Suite("Backups")
struct BackupTests {
    private func temporaryFolder() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("sip-backups-\(UUID().uuidString)", isDirectory: true)
    }

    @Test func fileNamesRoundTrip() {
        #expect(Backups.fileName(for: key("2026-10-06")) == "history-2026-10-06.json")
        #expect(Backups.day(fromFileName: "history-2026-10-06.json") == key("2026-10-06"))
        #expect(Backups.day(fromFileName: "history-2026-13-01.json") == nil)
        #expect(Backups.day(fromFileName: "history-2026-1-1.json") == nil)
        #expect(Backups.day(fromFileName: "notes.txt") == nil)
        #expect(Backups.day(fromFileName: "history.json") == nil)
    }

    @Test func keepsAWeekOfDaysThenOnePerWeek() {
        let existing = (0..<30).map { key("2026-09-07").adding(days: $0) }   // 7 Sep – 6 Oct
        let keep = Backups.toKeep(existing: existing, today: key("2026-10-06"))
        let daily = Set((0..<7).map { key("2026-10-06").adding(days: -$0) })
        // 30 Sep–6 Oct cover ISO weeks 40 and 41; then weeks 39, 38 and 37.
        #expect(keep == daily.union([key("2026-09-27"), key("2026-09-20"), key("2026-09-13")]))
        #expect(Backups.toKeep(existing: [], today: key("2026-10-06")).isEmpty)
        // A backup from a wrongly set future date is kept but takes no place.
        let future = Backups.toKeep(existing: existing + [key("2027-01-01")], today: key("2026-10-06"))
        #expect(future == keep.union([key("2027-01-01")]))
    }

    @Test func runCopiesOncePerDayAndPrunes() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let historyURL = root.appendingPathComponent("history.json")
        let folder = root.appendingPathComponent("Backups", isDirectory: true)
        try HistoryFile.save(HydrationHistory(entries: [Entry(date: at(10, 6, 9), amountML: 250),
                                                        Entry(date: at(10, 6, 10), amountML: 300)]), to: historyURL)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for offset in 1...40 {
            let name = Backups.fileName(for: key("2026-10-06").adding(days: -offset))
            try Data("{}".utf8).write(to: folder.appendingPathComponent(name))
        }
        try Data("keep me".utf8).write(to: folder.appendingPathComponent("notes.txt"))

        #expect(try Backups.run(historyURL: historyURL, folder: folder, today: key("2026-10-06")))
        #expect(try !Backups.run(historyURL: historyURL, folder: folder, today: key("2026-10-06")))
        let names = Set(try FileManager.default.contentsOfDirectory(atPath: folder.path))
        let days = Set(names.compactMap(Backups.day(fromFileName:)))
        let existing = (0...40).map { key("2026-10-06").adding(days: -$0) }
        #expect(days == Backups.toKeep(existing: existing, today: key("2026-10-06")))
        #expect(names.contains("notes.txt"))

        let list = Backups.list(folder: folder)
        #expect(list.first?.day == key("2026-10-06"))
        #expect(list.first?.entryCount == 2)
        #expect((list.first?.size ?? 0) > 0)
        #expect(list.dropFirst().allSatisfy { $0.entryCount == nil })
        #expect(zip(list, list.dropFirst()).allSatisfy { $0.day > $1.day })
    }

    @Test func runWithoutHistoryCopiesNothing() throws {
        let root = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Backups", isDirectory: true)
        #expect(try !Backups.run(historyURL: root.appendingPathComponent("missing.json"), folder: folder,
                                 today: key("2026-10-06")))
        #expect(Backups.list(folder: folder).isEmpty)
    }
}
