import Foundation
import Observation
import SipCore

/// The live history plus everything derived from it that the UI shows. All
/// derived values are recomputed together after each change, so views never
/// see a total that disagrees with the streak beside it.
@MainActor
@Observable
final class HydrationStore {
    private(set) var history = HydrationHistory()
    private(set) var today: DayKey
    private(set) var todaySummary: DaySummary
    private(set) var todayEntries: [Entry] = []
    private(set) var summaries: [DayKey: DaySummary] = [:]
    private(set) var streak: StreakResult = .zero
    /// Missed days that a comeback the next day repaired.
    private(set) var repairs: Set<DayKey> = []
    private(set) var loadError: String?

    /// Extra goal for today's weather, added on top of the daily goal.
    private(set) var goalBonusML: Double = 0
    /// Today has a workout on the calendar.
    private(set) var workoutToday = false
    private(set) var fileURL: URL

    @ObservationIgnored let settings: SettingsStore
    /// Off in demo mode: made-up history must never reach the real file.
    @ObservationIgnored private let persists: Bool
    @ObservationIgnored var onChange: (() -> Void)?
    /// When the file on disk was last read or written by this Mac, to tell our
    /// own saves from another Mac's.
    @ObservationIgnored private var knownModification: Date?

    init(settings: SettingsStore, demo: Bool) {
        self.settings = settings
        fileURL = SipPaths.dataFolder(iCloud: settings.iCloudSync).appendingPathComponent(SipPaths.historyFileName)
        persists = !demo
        let clock = DayClock(dayStartHour: settings.dayStartHour)
        let todayKey = clock.key(for: Date())
        today = todayKey
        todaySummary = .empty(todayKey, goal: settings.dailyGoalML)

        if demo {
            history = DemoData.make(settings: settings, clock: clock)
        } else {
            do {
                history = try HistoryFile.load(from: fileURL)
                knownModification = modificationDate()
            } catch {
                // Keep the unreadable file untouched; start empty in memory.
                loadError = error.localizedDescription
                history = HydrationHistory()
            }
        }
        recompute()
    }

    // MARK: Derived

    var clock: DayClock { DayClock(dayStartHour: settings.dayStartHour) }
    /// Today's goal before any day-specific record: the setting plus weather.
    /// Today's goal before it's stored: your goal (or this weekday's), plus a
    /// workout bonus, plus the weather's.
    var baseGoal: Double {
        settings.weeklySchedule.goal(for: today, base: settings.dailyGoalML, hasWorkoutEvent: workoutToday) + goalBonusML
    }
    var goal: Double { max(todaySummary.goalML, 1) }
    var consumed: Double { todaySummary.effectiveML }
    var progress: Double { consumed / goal }
    var lastSip: Date? { history.entries.last?.date }
    var lastEntry: Entry? { history.entries.last }
    var firstDay: DayKey? { history.entries.first.map { clock.key(for: $0.date) } }

    /// Today's drinks as bottom-up bands, one per kind: other drinks settle
    /// in the order you had them, and water always sits on top. Grouping keeps
    /// a day of alternating tea and water from reading as stripes.
    var todayLayers: [LiquidLayer] {
        var order: [DrinkKind] = []
        var totals: [DrinkKind: Double] = [:]
        for entry in todayEntries {
            if totals[entry.drink] == nil { order.append(entry.drink) }
            totals[entry.drink, default: 0] += entry.effectiveML(settings.factors) / goal
        }
        let watery: Set<DrinkKind> = [.water, .sparkling]
        let sorted = order.filter { !watery.contains($0) } + order.filter { watery.contains($0) }
        return sorted.map { LiquidLayer(drink: $0, fraction: totals[$0] ?? 0) }
    }

    /// More bubbles when the latest drink was carbonated.
    var fizz: Double { todayEntries.last?.drink.isCarbonated == true ? 3 : 1 }

    func summary(for key: DayKey) -> DaySummary {
        summaries[key] ?? .empty(key, goal: history.goal(for: key, fallback: settings.dailyGoalML))
    }

    /// The last `count` days ending today, oldest first, including empty days.
    func recentDays(_ count: Int) -> [DaySummary] {
        (0..<count).reversed().map { summary(for: today.adding(days: -$0)) }
    }

    func entries(on key: DayKey) -> [Entry] {
        HistoryMath.entries(on: key, in: history, clock: clock)
    }

    func pace(at now: Date) -> PaceStatus {
        let expected = Pace.expectedFraction(at: now, on: today, hours: settings.activeHours, clock: clock)
        return Pace.status(consumed: consumed, goal: goal, expectedFraction: expected)
    }

    func expectedFraction(at now: Date) -> Double {
        Pace.expectedFraction(at: now, on: today, hours: settings.activeHours, clock: clock)
    }

    /// Today's wake and sleep times.
    var wakingWindow: (wake: Date, sleep: Date) {
        let window = settings.activeHours.window(on: today, clock: clock)
        return (window.wake, window.sleep)
    }

    // MARK: Changes

    @discardableResult
    func add(ml: Double, drink: DrinkKind, at date: Date = Date()) -> Entry {
        let entry = Entry(date: date, amountML: ml, drink: drink)
        let key = clock.key(for: date)
        if history.dayGoals[key.description] == nil {
            history.dayGoals[key.description] = key == today
                ? baseGoal
                : history.goal(for: key, fallback: settings.dailyGoalML)
        }
        history.insert(entry)
        commit()
        return entry
    }

    func delete(_ id: UUID) {
        guard history.remove(id: id) != nil else { return }
        commit()
    }

    /// The goal setting changed: today takes the new goal; earlier days keep theirs.
    func goalChanged() {
        history.dayGoals[today.description] = baseGoal
        commit()
    }

    /// Weather changed today's bonus.
    func setGoalBonus(_ bonus: Double) {
        guard bonus != goalBonusML else { return }
        goalBonusML = bonus
        goalChanged()
    }

    func setWorkoutToday(_ workout: Bool) {
        guard workout != workoutToday else { return }
        workoutToday = workout
        goalChanged()
    }

    // MARK: Sync

    /// Moves history between the local folder and iCloud Drive, merging with
    /// whatever is already at the destination.
    func relocate(iCloud: Bool) {
        let target = SipPaths.dataFolder(iCloud: iCloud).appendingPathComponent(SipPaths.historyFileName)
        guard target != fileURL else { return }
        fileURL = target
        knownModification = nil
        if let there = try? HistoryFile.load(from: target) {
            history = history.merged(with: there)
        }
        commit()
    }

    /// The file changed on disk: another Mac saved. Merge it in.
    func reloadIfChangedOnDisk() {
        guard persists, let modified = modificationDate(), modified != knownModification,
              let there = try? HistoryFile.load(from: fileURL) else { return }
        knownModification = modified
        let merged = history.merged(with: there)
        guard merged != history else { return }
        history = merged
        recompute()
    }

    private func modificationDate() -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: fileURL.path))?[.modificationDate] as? Date
    }

    func importEntries(_ entries: [Entry]) {
        let existing = Set(history.entries.map { "\($0.date.timeIntervalSince1970)-\($0.amountML)" })
        for entry in entries where !existing.contains("\(entry.date.timeIntervalSince1970)-\(entry.amountML)") {
            history.insert(entry)
        }
        commit()
    }

    func resetAll() {
        history.removeAll()
        commit()
    }

    /// Replaces the whole history with a backup. Deletions since then are
    /// kept as deletions only if they're in the backup too.
    func restore(from url: URL) throws {
        let restored = try HistoryFile.load(from: url)
        // Keep what's being replaced, just in case.
        let keep = SipPaths.backupsFolder.appendingPathComponent("before-restore-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.createDirectory(at: SipPaths.backupsFolder, withIntermediateDirectories: true)
        try? HistoryFile.save(history, to: keep)
        history = restored
        commit()
    }

    /// Re-derives everything. Also called when the day rolls over or a setting
    /// that affects totals (day start, hydration factors) changes.
    func recompute(now: Date = Date()) {
        let clock = self.clock
        today = clock.key(for: now)
        summaries = HistoryMath.summaries(history, clock: clock, factors: settings.factors,
                                          fallbackGoal: settings.dailyGoalML)
        // Today with no entries still shows the current goal.
        todaySummary = summaries[today]
            ?? .empty(today, goal: history.dayGoals[today.description] ?? baseGoal)
        todayEntries = HistoryMath.entries(on: today, in: history, clock: clock)
        let met = Set(summaries.values.filter(\.met).map(\.key))
        // A missed day made up for by a big day after it (once a month).
        repairs = Comeback.repairs(summaries: summaries, today: today)
        streak = Streaks.compute(metDays: met, firstDay: firstDay, today: today,
                                 freezesEnabled: settings.streakFreezes, repairs: repairs)
        onChange?()
    }

    private func commit() {
        if persists {
            do {
                // Someone else (another Mac) wrote since we last looked: fold
                // their changes in rather than overwriting them.
                if let modified = modificationDate(), modified != knownModification,
                   let there = try? HistoryFile.load(from: fileURL) {
                    history = history.merged(with: there)
                }
                try HistoryFile.save(history, to: fileURL)
                knownModification = modificationDate()
                loadError = nil
            } catch {
                loadError = "Couldn't save: \(error.localizedDescription)"
            }
        }
        recompute()
    }

    func exportCSV() -> String { HistoryCSV.export(history) }
}

/// Made-up but plausible history for screenshots and checks: mostly water,
/// spread across waking hours, with a current streak and one frozen day.
enum DemoData {
    static func make(settings: SettingsStore, clock: DayClock) -> HydrationHistory {
        var generator = SeededGenerator(seed: 42)
        var history = HydrationHistory()
        let goal = settings.dailyGoalML
        let today = clock.key(for: Date())
        let drinks: [(DrinkKind, Double)] = [(.water, 0.62), (.tea, 0.12), (.coffee, 0.12), (.sparkling, 0.07), (.juice, 0.07)]
        for back in stride(from: 60, through: 1, by: -1) {
            let key = today.adding(days: -back)
            history.dayGoals[key.description] = goal
            // A handful of short days, but the last twelve all met except one
            // that a freeze covers.
            let shortDay = (back > 13 && back % 9 == 0) || back == 6
            let target = goal * (shortDay ? Double.random(in: 0.45...0.8, using: &generator)
                                          : Double.random(in: 1.0...1.25, using: &generator))
            var total = 0.0
            var minute = settings.wakeMinutes + Int.random(in: 10...50, using: &generator)
            // Spread the day's drinks across waking hours whatever the goal is.
            let spacing = max((settings.sleepMinutes - settings.wakeMinutes) * 250 / Int(max(target, 1)) * 9 / 10, 12)
            while total < target {
                let amount = [150.0, 200, 250, 250, 300, 350, 500].randomElement(using: &generator)!
                var pick = Double.random(in: 0...1, using: &generator)
                var drink = DrinkKind.water
                for (kind, weight) in drinks {
                    if pick < weight { drink = kind; break }
                    pick -= weight
                }
                history.insert(Entry(date: clock.time(minute, on: key), amountML: amount, drink: drink))
                total += amount * drink.defaultHydrationFactor
                minute = min(minute + Int.random(in: spacing / 2...max(spacing, spacing / 2 + 1), using: &generator),
                             settings.sleepMinutes - 5)
            }
        }
        // Today: part-way there.
        let now = Date()
        var minute = settings.wakeMinutes + 20
        var total = 0.0
        while clock.time(minute, on: today) < now, total < goal * 0.55 {
            let amount = [200.0, 250, 300].randomElement(using: &generator)!
            let drink: DrinkKind = total == 0 ? .water : (Bool.random(using: &generator) ? .water : .tea)
            history.insert(Entry(date: clock.time(minute, on: today), amountML: amount, drink: drink))
            total += amount
            minute += 75
        }
        // `goalmet`: today is already done, the state the flame used to burn
        // CPU in. Benchmarks run it so that can't come back unnoticed.
        if DebugHooks.has("goalmet"), total < goal * 1.05 {
            history.insert(Entry(date: now.addingTimeInterval(-60), amountML: goal * 1.05 - total, drink: .water))
        }
        history.dayGoals[today.description] = goal
        return history
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
