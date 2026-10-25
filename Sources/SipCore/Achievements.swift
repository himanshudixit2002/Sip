import Foundation

/// How hard a badge is to earn, for its frame and sort order.
public enum AchievementRarity: String, CaseIterable, Codable, Sendable, Comparable {
    case common
    case rare
    case epic
    case legendary

    public var title: String { rawValue.capitalized }

    public static func < (lhs: AchievementRarity, rhs: AchievementRarity) -> Bool {
        let order = AchievementRarity.allCases
        return (order.firstIndex(of: lhs) ?? 0) < (order.firstIndex(of: rhs) ?? 0)
    }
}

public struct AchievementStatus: Equatable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var progress: Double      // 0–1
    public var progressText: String
    public var rarity: AchievementRarity = .common
    public var unlocked: Bool { progress >= 1 }
}

/// Badges, all derived from history so they can never disagree with it.
public enum Achievements {
    public struct Input {
        public var history: HydrationHistory
        public var summaries: [DayKey: DaySummary]
        public var bestStreak: Int
        public var clock: DayClock
        public var bottleML: Double
        /// For badges that look at single drinks' effective amounts.
        public var factors: HydrationFactors
        /// The forecast high for days the weather was known, in °C.
        public var maxTemperatureByDay: [DayKey: Double]
        /// Days whose daily challenge was completed (`Challenges.completedDays`).
        public var challengeDays: Set<DayKey>
        /// Missed days won back (`Comeback.repairs`).
        public var repairedDays: Set<DayKey>
        /// Days the person followed the day plan.
        public var plannedFollowDays: Set<DayKey>
        /// The current level (`XP.level(forXP:)`), 0 when unknown.
        public var level: Int

        public init(history: HydrationHistory, summaries: [DayKey: DaySummary], bestStreak: Int,
                    clock: DayClock, bottleML: Double, factors: HydrationFactors = HydrationFactors(),
                    maxTemperatureByDay: [DayKey: Double] = [:], challengeDays: Set<DayKey> = [],
                    repairedDays: Set<DayKey> = [], plannedFollowDays: Set<DayKey> = [], level: Int = 0) {
            self.history = history
            self.summaries = summaries
            self.bestStreak = bestStreak
            self.clock = clock
            self.bottleML = bottleML
            self.factors = factors
            self.maxTemperatureByDay = maxTemperatureByDay
            self.challengeDays = challengeDays
            self.repairedDays = repairedDays
            self.plannedFollowDays = plannedFollowDays
            self.level = level
        }
    }

    public static func evaluate(_ input: Input) -> [AchievementStatus] {
        let entries = input.history.entries
        let clock = input.clock
        let days = input.summaries.values
        let totalML = entries.reduce(0) { $0 + $1.amountML }
        let metDays = days.filter(\.met).count
        let bestRatio = days.map(\.progress).max() ?? 0
        let busiestMetDay = days.filter(\.met).map(\.entryCount).max() ?? 0
        let kinds = Set(entries.map(\.drink)).count
        let byDay = HistoryMath.entriesByDay(entries, clock: clock)

        // First drink of each day before 09:00.
        var earlyDays = 0
        var mostBottles = 0
        // Met days with 30% or more after 8 PM; best share on any met day.
        var bestLateShare = 0.0
        // Met days where the goal was reached before 3 PM.
        var earlyFinish = false
        // Days with drinks in 8 or more different hours.
        var steadyDays = 0
        for (key, list) in byDay {
            if let first = list.first, clock.calendar.component(.hour, from: first.date) < 9 { earlyDays += 1 }
            mostBottles = max(mostBottles, list.filter { $0.amountML >= input.bottleML - 0.5 }.count)
            if Set(list.map { clock.calendar.component(.hour, from: $0.date) }).count >= 8 { steadyDays += 1 }
            guard let summary = input.summaries[key], summary.met else { continue }
            let eight = clock.time(20 * 60, on: key)
            let three = clock.time(15 * 60, on: key)
            var late = 0.0
            var running = 0.0
            for entry in list {
                let value = entry.effectiveML(input.factors)
                if entry.date >= eight { late += value }
                running += value
                if !earlyFinish, running >= summary.goalML - 0.5, entry.date < three { earlyFinish = true }
            }
            if summary.effectiveML > 0 { bestLateShare = max(bestLateShare, late / summary.effectiveML) }
        }

        // A Monday-to-Sunday week with every day met.
        var perfectWeek = false
        var bestWeekRun = 0
        for summary in days where summary.met && summary.key.weekday == 2 {
            var run = 0
            var day = summary.key
            while run < 7, input.summaries[day]?.met == true {
                run += 1
                day = day.next
            }
            bestWeekRun = max(bestWeekRun, run)
            if run == 7 { perfectWeek = true; break }
        }

        // Weekends with both Saturday and Sunday met.
        let fullWeekends = days.filter { $0.met && $0.key.weekday == 7 && input.summaries[$0.key.next]?.met == true }.count

        // The calendar month with the largest share of days met.
        var metByMonth: [Int: Int] = [:]
        for summary in days where summary.met { metByMonth[summary.key.year * 12 + summary.key.month - 1, default: 0] += 1 }
        // Months in order, so ties always resolve to the same month.
        var bestMonth = (met: 0, length: 30)
        for index in metByMonth.keys.sorted() {
            let met = metByMonth[index] ?? 0
            let first = DayKey(year: index / 12, month: index % 12 + 1, day: 1)
            let length = first.days(to: index % 12 == 11 ? DayKey(year: first.year + 1, month: 1, day: 1)
                                                           : DayKey(year: first.year, month: first.month + 1, day: 1))
            if met * bestMonth.length > bestMonth.met * length { bestMonth = (met, length) }
        }

        // Longest run of consecutive logged days without coffee.
        var coffeeFreeRun = 0
        var run = 0
        var previous: DayKey?
        for summary in days.sorted(by: { $0.key < $1.key }) where summary.entryCount > 0 {
            let clean = (summary.byDrink[.coffee] ?? 0) <= 0
            if clean, let previous, previous.next == summary.key, run > 0 { run += 1 } else { run = clean ? 1 : 0 }
            coffeeFreeRun = max(coffeeFreeRun, run)
            previous = summary.key
        }

        let hotMetDay = days.contains { $0.met && (input.maxTemperatureByDay[$0.key] ?? -100) >= 35 }
        let teas = entries.filter { $0.drink == .tea }.count
        let sparkling = entries.filter { $0.drink == .sparkling }.count
        let challenges = input.challengeDays.count

        func badge(_ id: String, _ title: String, _ detail: String, _ symbol: String, _ rarity: AchievementRarity,
                   _ value: Double, _ target: Double, _ format: (Double) -> String = { "\(Int($0))" }) -> AchievementStatus {
            let p = target > 0 ? min(value / target, 1) : 0
            return AchievementStatus(id: id, title: title, detail: detail, symbol: symbol, progress: p,
                                     progressText: "\(format(min(value, target))) / \(format(target))", rarity: rarity)
        }
        let litres: (Double) -> String = { "\(Int(($0 / 1000).rounded(.down))) L" }
        let percent: (Double) -> String = { "\(Int($0))%" }

        return [
            badge("first_sip", "First Sip", "Log your first drink.", "drop.fill", .common, Double(entries.count), 1),
            badge("goal_getter", "Goal Getter", "Reach your daily goal.", "checkmark.seal.fill", .common, Double(metDays), 1),
            badge("streak_3", "Warming Up", "A 3-day streak.", "flame", .common, Double(input.bestStreak), 3),
            badge("streak_7", "One Week Strong", "A 7-day streak.", "flame.fill", .rare, Double(input.bestStreak), 7),
            badge("streak_14", "Fortnight Flow", "A 14-day streak.", "water.waves", .rare, Double(input.bestStreak), 14),
            badge("streak_30", "Hydration Habit", "A 30-day streak.", "medal.fill", .epic, Double(input.bestStreak), 30),
            badge("streak_100", "Centurion", "A 100-day streak.", "crown.fill", .legendary, Double(input.bestStreak), 100),
            badge("perfect_week", "Perfect Week", "Every day of a Monday–Sunday week.", "calendar.badge.checkmark", .rare,
                  perfectWeek ? 7 : Double(bestWeekRun), 7),
            badge("early_bird", "Early Bird", "First drink before 9 AM on 10 days.", "sunrise.fill", .common,
                  Double(earlyDays), 10),
            badge("little_often", "Little and Often", "Reach the goal with 8 or more drinks in a day.",
                  "circle.grid.3x3.fill", .common, Double(busiestMetDay), 8),
            badge("overachiever", "Overflowing", "Drink 150% of your goal in a day.", "arrow.up.forward.circle.fill", .rare,
                  bestRatio * 100, 150, percent),
            badge("variety", "Mixologist", "Log 5 different kinds of drink.", "cup.and.saucer.fill", .common, Double(kinds), 5),
            badge("refills", "Refill Master", "Finish your bottle 4 times in one day.", "arrow.triangle.2.circlepath", .rare,
                  Double(mostBottles), 4),
            badge("litres_100", "100 Litres", "Drink 100 litres in total.", "drop.circle.fill", .rare, totalML, 100_000, litres),
            badge("litres_500", "Reservoir", "Drink 500 litres in total.", "humidity.fill", .epic, totalML, 500_000, litres),

            // Version 2.
            badge("night_owl", "Night Owl", "Meet your goal with 30% or more of it after 8 PM.", "moon.stars.fill", .common,
                  (bestLateShare * 100).rounded(.down), 30, percent),
            badge("weather_warrior", "Weather Warrior", "Meet your goal on a day of 35 °C or more.", "thermometer.sun.fill",
                  .rare, hotMetDay ? 1 : 0, 1),
            badge("comeback", "Comeback", "Win back a missed day with 110% the day after.", "arrow.uturn.up.circle.fill",
                  .common, Double(input.repairedDays.count), 1),
            badge("challenger_1", "Challenger", "Complete a daily challenge.", "flag.fill", .common, Double(challenges), 1),
            badge("challenger_10", "Challenge Accepted", "Complete 10 daily challenges.", "flag.2.crossed.fill", .rare,
                  Double(challenges), 10),
            badge("challenger_50", "Challenge Champion", "Complete 50 daily challenges.", "trophy.fill", .epic,
                  Double(challenges), 50),
            badge("planner", "Planner", "Follow your day plan on 5 days.", "calendar.day.timeline.left", .common,
                  Double(input.plannedFollowDays.count), 5),
            badge("coffee_free_week", "Decaf Week", "Seven logged days in a row without coffee.", "leaf.fill", .rare,
                  Double(coffeeFreeRun), 7),
            badge("streak_365", "Year of Water", "A 365-day streak.", "sparkles", .legendary, Double(input.bestStreak), 365),
            badge("litres_1000", "Thousand Litres", "Drink 1,000 litres in total.", "cloud.rain.fill",
                  .legendary, totalML, 1_000_000, litres),
            badge("early_finisher", "Early Finisher", "Reach your goal before 3 PM.", "flag.checkered", .rare,
                  earlyFinish ? 1 : 0, 1),
            badge("weekend_warrior", "Weekend Warrior", "Meet your goal on both days of 4 weekends.", "figure.walk", .rare,
                  Double(fullWeekends), 4),
            badge("centurion", "Hundred Club", "Meet your goal on 100 days.", "rosette", .epic, Double(metDays), 100),
            badge("marathon", "Marathon", "Drink 200% of your goal in a day.", "figure.run", .epic, bestRatio * 100, 200, percent),
            badge("tea_time", "Tea Time", "Log 50 cups of tea.", "cup.and.heat.waves.fill", .common, Double(teas), 50),
            badge("sparkle", "Sparkle", "Log 25 sparkling drinks.", "bubbles.and.sparkles.fill", .common, Double(sparkling), 25),
            badge("steady", "Steady Sipper", "Drink in 8 different hours on 10 days.", "clock.badge.checkmark.fill", .rare,
                  Double(steadyDays), 10),
            badge("perfect_month", "Perfect Month", "Meet your goal on every day of a calendar month.", "calendar.circle.fill",
                  .legendary, Double(bestMonth.met), Double(bestMonth.length)),
            badge("level_10", "Pond Life", "Reach level 10.", "10.circle.fill", .rare, Double(input.level), 10),
            badge("level_20", "Gulf Stream", "Reach level 20.", "20.circle.fill", .epic, Double(input.level), 20),
        ]
    }
}
