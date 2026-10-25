import Foundation
import Testing
@testable import SipCore

private let calendar: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Asia/Kolkata")!
    return c
}()

private func at(_ h: Int, _ min: Int = 0, day: Int = 6) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: min))!
}

private let rates = CaffeineRates()
/// 250 ml of coffee at 9:00 is 100 mg, fully absorbed by 9:30.
private let coffee = [Entry(date: at(9), amountML: 250, drink: .coffee), Entry(date: at(10), amountML: 500)]

private func close(_ a: Double, _ b: Double, _ tolerance: Double = 0.01) -> Bool { abs(a - b) < tolerance }
private func close(_ a: Date?, _ b: Date, seconds: Double = 2) -> Bool {
    guard let a else { return false }
    return abs(a.timeIntervalSince(b)) < seconds
}

@Suite("Caffeine model")
struct CaffeineModelTests {
    @Test func absorbsOverHalfAnHourThenHalvesEveryHalfLife() {
        #expect(CaffeineModel.level(at: at(8), entries: coffee, rates: rates) == 0)
        #expect(close(CaffeineModel.level(at: at(9, 15), entries: coffee, rates: rates), 50))
        #expect(close(CaffeineModel.level(at: at(9, 30), entries: coffee, rates: rates), 100))
        #expect(close(CaffeineModel.level(at: at(14, 30), entries: coffee, rates: rates), 50))
        #expect(close(CaffeineModel.level(at: at(19, 30), entries: coffee, rates: rates), 25))
        #expect(close(CaffeineModel.level(at: at(14, 30), entries: coffee, rates: rates, halfLifeHours: 2.5), 25))
    }

    @Test func yesterdaysCoffeeStillCounts() {
        let late = [Entry(date: at(22, day: 5), amountML: 250, drink: .coffee)]
        // 22:30 to 07:30 is 9 hours: 100 × 2^(−9/5).
        #expect(close(CaffeineModel.level(at: at(7, 30), entries: late, rates: rates), 100 * pow(2, -1.8)))
    }

    @Test func clearTimeSolvesTheDecay() {
        #expect(close(CaffeineModel.clearTime(below: 50, after: at(10), entries: coffee, rates: rates), at(14, 30)))
        // A drink not yet absorbed is taken into account.
        #expect(close(CaffeineModel.clearTime(below: 50, after: at(8), entries: coffee, rates: rates), at(14, 30)))
        // Already under with nothing pending.
        #expect(CaffeineModel.clearTime(below: 50, after: at(20), entries: coffee, rates: rates) == nil)
        #expect(CaffeineModel.clearTime(below: 50, after: at(8), entries: [], rates: rates) == nil)
        // A small tea never lifts it over.
        let tea = [Entry(date: at(9), amountML: 50, drink: .tea)]
        #expect(CaffeineModel.clearTime(below: 50, after: at(8), entries: tea, rates: rates) == nil)
    }

    @Test func clearTimeFindsTheLastCrossingBeforeALaterSmallDrink() {
        let entries = coffee + [Entry(date: at(20), amountML: 50, drink: .tea)]
        #expect(close(CaffeineModel.clearTime(below: 50, after: at(9), entries: entries, rates: rates), at(14, 30)))
    }

    @Test func curveSamplesEveryStep() {
        let points = CaffeineModel.curve(from: at(9), to: at(10), step: 900, entries: coffee, rates: rates)
        #expect(points.map(\.date) == [at(9), at(9, 15), at(9, 30), at(9, 45), at(10)])
        #expect(close(points[1].mg, 50))
        #expect(close(points[4].mg, 100 * pow(2, -0.1)))
        #expect(CaffeineModel.curve(from: at(10), to: at(9), entries: coffee, rates: rates).isEmpty)
        #expect(CaffeineModel.curve(from: at(9), to: at(10), step: 0, entries: coffee, rates: rates).isEmpty)
    }

    @Test func levelAtBedtimeAddsTheProposedDrink() {
        #expect(close(CaffeineModel.levelAtBedtime(ifAdding: 100, at: at(18), bedtime: at(23, 30), entries: [], rates: rates), 50))
        let withMorning = CaffeineModel.levelAtBedtime(ifAdding: 100, at: at(18), bedtime: at(23, 30), entries: coffee,
                                                       rates: rates)
        #expect(close(withMorning, 50 + 100 * pow(2, -2.8)))
    }
}
