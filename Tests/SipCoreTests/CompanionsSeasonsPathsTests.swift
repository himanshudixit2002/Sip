import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
}

private func season(_ y: Int, _ m: Int, _ d: Int) -> SeasonPack? { Seasons.active(on: date(y, m, d), calendar: calendar) }

@Suite("Companions")
struct CompanionTests {
    @Test func fishJoinAtStreakMilestones() {
        #expect([0, 6, 7, 29, 30, 99, 100, 400].map(Companions.fishCount) == [1, 1, 2, 2, 3, 3, 4, 4])
    }

    @Test func plantGrowsFlowersAndDroops() {
        #expect(Companions.plant(metLast14: 0, streak: 0, behindPace: false) == PlantState(leaves: 0, flowering: false, droop: 0))
        #expect(Companions.plant(metLast14: 1, streak: 1, behindPace: false).leaves == 1)
        #expect(Companions.plant(metLast14: 7, streak: 6, behindPace: false).leaves == 4)
        #expect(Companions.plant(metLast14: 14, streak: 7, behindPace: true) == PlantState(leaves: 8, flowering: true, droop: 0.6))
        #expect(Companions.plant(metLast14: 40, streak: 0, behindPace: false).leaves == 8)
    }
}

@Suite("Seasons")
struct SeasonTests {
    @Test func festivals() {
        #expect(season(2026, 11, 8) == .diwali)
        #expect(season(2026, 11, 6) == .diwali)
        #expect(season(2026, 11, 10) == .diwali)
        #expect(season(2026, 11, 5) == nil)
        #expect(season(2027, 10, 31) == .diwali)
        #expect(season(2026, 3, 3) == .holi)
        #expect(season(2026, 3, 4) == .holi)
        #expect(season(2026, 3, 5) == nil)
        #expect(season(2026, 12, 25) == .christmas)
        #expect(season(2026, 12, 31) == .newYear)
        #expect(season(2027, 1, 1) == .newYear)
    }

    @Test func seasonsFillTheRest() {
        #expect(season(2026, 6, 9) == nil)
        #expect(season(2026, 6, 10) == .monsoon)
        #expect(season(2026, 9, 30) == .monsoon)
        #expect(season(2026, 10, 1) == nil)
        #expect(season(2026, 12, 1) == .winter)
        #expect(season(2026, 12, 27) == .winter)
        #expect(season(2027, 2, 28) == .winter)
        #expect(season(2028, 2, 29) == .winter)
        #expect(season(2027, 3, 1) == nil)
    }

    @Test func glassMoodRamps() {
        #expect(GlassMood.make(temperatureC: nil, humidity: nil, weatherCode: nil) == .neutral)
        let cold = GlassMood.make(temperatureC: 6, humidity: 85, weatherCode: 61)
        #expect(cold.frost == 0.5 && cold.humid == 0.5 && cold.rain && cold.heat == 0)
        let hot = GlassMood.make(temperatureC: 35, humidity: 40, weatherCode: 1)
        #expect(hot.heat == 0.5 && hot.frost == 0 && hot.humid == 0 && !hot.rain)
        #expect(GlassMood.make(temperatureC: -5, humidity: 100, weatherCode: 95) == GlassMood(frost: 1, rain: true, humid: 1, heat: 0))
        #expect(GlassMood.make(temperatureC: 45, humidity: nil, weatherCode: 3).heat == 1)
    }

    @Test func weatherKinds() {
        let codes = [0, 2, 45, 53, 63, 81, 73, 96, 999]
        #expect(codes.map(WeatherKind.init(wmoCode:)) == [.clear, .cloudy, .fog, .drizzle, .rain, .rain, .snow, .storm, .cloudy])
        #expect([51, 67, 80, 82, 95, 99].allSatisfy(WeatherKind.isWet))
        #expect(![0, 3, 45, 71, 85, 50, 68].contains(where: WeatherKind.isWet))
    }
}

@Suite("Time markers")
struct TimeMarkerTests {
    @Test func marksEveryTwoHoursAlongThePaceLine() {
        let marks = TimeMarkers.marks(wakeMinutes: 7 * 60, sleepMinutes: 23 * 60)
        #expect(marks.map(\.minutes) == [8, 10, 12, 14, 16, 18, 20, 22].map { $0 * 60 })
        #expect(marks.map(\.label) == ["8 AM", "10 AM", "12 PM", "2 PM", "4 PM", "6 PM", "8 PM", "10 PM"])
        #expect(marks.first?.fraction == 1.0 / 16)
        #expect(marks.last?.fraction == 15.0 / 16)
        let late = TimeMarkers.marks(wakeMinutes: 7 * 60 + 30, sleepMinutes: 23 * 60, everyMinutes: 60)
        #expect(late.first?.label == "9 AM")
        #expect(late.count == 15)
    }

    @Test func bedtimeAfterMidnight() {
        let marks = TimeMarkers.marks(wakeMinutes: 10 * 60, sleepMinutes: 60)
        #expect(marks.first?.label == "11 AM")
        #expect(marks.last?.label == "1 AM")
        #expect(marks.last?.minutes == 25 * 60)
        #expect(marks.last?.fraction == 1)
    }

    @Test func nextMark() {
        let marks = TimeMarkers.marks(wakeMinutes: 7 * 60, sleepMinutes: 23 * 60)
        #expect(TimeMarkers.nextMark(marks, nowMinutes: 9 * 60 + 30)?.label == "10 AM")
        #expect(TimeMarkers.nextMark(marks, nowMinutes: 10 * 60)?.label == "12 PM")
        #expect(TimeMarkers.nextMark(marks, nowMinutes: 22 * 60 + 5) == nil)
        #expect(clockLabel(0) == "12 AM" && clockLabel(13 * 60 + 5) == "1:05 PM")
    }
}

@Suite("Paths")
struct PathTests {
    private func fakeHome(iCloud: Bool, shortcuts: Bool) throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("sip-home-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        if iCloud {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs"), withIntermediateDirectories: true)
        }
        if shortcuts {
            try FileManager.default.createDirectory(
                at: home.appendingPathComponent("Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents"),
                withIntermediateDirectories: true)
        }
        return home
    }

    @Test func dataFolderPrefersOverrideThenICloudThenLocal() throws {
        let home = try fakeHome(iCloud: true, shortcuts: false)
        defer { try? FileManager.default.removeItem(at: home) }
        let local = home.appendingPathComponent("Library/Application Support/Sip", isDirectory: true)
        let cloud = home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Sip", isDirectory: true)
        #expect(SipPaths.dataFolder(iCloud: false, home: home, environment: [:]) == local)
        #expect(SipPaths.dataFolder(iCloud: true, home: home, environment: [:]) == cloud)
        let env = ["SIP_DATA_DIR": "/tmp/sip-debug"]
        #expect(SipPaths.dataFolder(iCloud: true, home: home, environment: env) == URL(fileURLWithPath: "/tmp/sip-debug", isDirectory: true))
        #expect(SipPaths.dataFolder(iCloud: false, home: home, environment: ["SIP_DATA_DIR": ""]) == local)
        #expect(SipPaths.backupsFolder(home: home, environment: [:]) == local.appendingPathComponent("Backups", isDirectory: true))
        #expect(SipPaths.backupsFolder(home: home, environment: env).path == "/tmp/sip-debug/Backups")

        let noCloud = try fakeHome(iCloud: false, shortcuts: false)
        defer { try? FileManager.default.removeItem(at: noCloud) }
        #expect(SipPaths.iCloudDrive(home: noCloud) == nil)
        #expect(SipPaths.dataFolder(iCloud: true, home: noCloud, environment: [:]) == SipPaths.localFolder(home: noCloud))
    }

    @Test func inboxFiles() throws {
        let home = try fakeHome(iCloud: true, shortcuts: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let files = SipPaths.inboxFiles(iCloud: false, home: home, environment: [:]).map(\.lastPathComponent)
        #expect(files == ["Inbox.txt", "Sip Inbox.txt", "Inbox.txt"])
        let overridden = SipPaths.inboxFiles(iCloud: true, home: home, environment: ["SIP_DATA_DIR": "/tmp/sip-debug"])
        #expect(overridden.map(\.path) == ["/tmp/sip-debug/Inbox.txt"])
        let bare = try fakeHome(iCloud: false, shortcuts: false)
        defer { try? FileManager.default.removeItem(at: bare) }
        #expect(SipPaths.inboxFiles(iCloud: true, home: bare, environment: [:]).count == 1)
    }
}
