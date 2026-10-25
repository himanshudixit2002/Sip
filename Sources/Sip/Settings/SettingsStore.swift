import AppKit
import Observation
import SipCore

/// Every preference, persisted to UserDefaults as it changes. Because reads go
/// through `UserDefaults.standard`, any key can be overridden for one launch
/// with a command-line argument (`-widgetSize large`) without touching the
/// saved value.
@Observable
final class SettingsStore {
    @ObservationIgnored private let defaults: UserDefaults

    // MARK: Goal

    var dailyGoalML: Double { didSet { defaults.set(dailyGoalML, forKey: "dailyGoalML") } }
    var unit: VolumeUnit { didSet { defaults.set(unit.rawValue, forKey: "unit") } }
    var dayStartHour: Int { didSet { defaults.set(dayStartHour, forKey: "dayStartHour") } }
    var wakeMinutes: Int { didSet { defaults.set(wakeMinutes, forKey: "wakeMinutes") } }
    var sleepMinutes: Int { didSet { defaults.set(sleepMinutes, forKey: "sleepMinutes") } }
    var weightKg: Double { didSet { defaults.set(weightKg, forKey: "weightKg") } }
    var exerciseMinutes: Double { didSet { defaults.set(exerciseMinutes, forKey: "exerciseMinutes") } }
    var hotClimate: Bool { didSet { defaults.set(hotClimate, forKey: "hotClimate") } }
    var streakFreezes: Bool { didSet { defaults.set(streakFreezes, forKey: "streakFreezes") } }

    // MARK: Drinks

    var cups: [Cup] { didSet { Self.store(cups, "cups", defaults) } }
    var defaultCupID: UUID? { didSet { defaults.set(defaultCupID?.uuidString, forKey: "defaultCupID") } }
    var factors: HydrationFactors { didSet { Self.store(factors, "factors", defaults) } }
    var disabledDrinks: Set<DrinkKind> { didSet { Self.store(disabledDrinks, "disabledDrinks", defaults) } }

    // MARK: Appearance

    var bottleStyle: BottleStyle { didSet { defaults.set(bottleStyle.rawValue, forKey: "bottleStyle") } }
    var customBottle: CustomBottleSpec { didSet { Self.store(customBottle, "customBottle", defaults) } }
    var bottleLabel: String { didSet { defaults.set(bottleLabel, forKey: "bottleLabel") } }
    var glassTint: GlassTint { didSet { defaults.set(glassTint.rawValue, forKey: "glassTint") } }
    var theme: LiquidTheme { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
    var layeredDrinks: Bool { didSet { defaults.set(layeredDrinks, forKey: "layeredDrinks") } }
    var cardBackground: CardBackground { didSet { defaults.set(cardBackground.rawValue, forKey: "cardBackground") } }
    var cardOpacity: Double { didSet { defaults.set(cardOpacity, forKey: "cardOpacity") } }
    var widgetSize: WidgetSize { didSet { defaults.set(widgetSize.rawValue, forKey: "widgetSize") } }
    var widgetScale: Double { didSet { defaults.set(widgetScale, forKey: "widgetScale") } }
    var motion: MotionLevel { didSet { defaults.set(motion.rawValue, forKey: "motion") } }
    var maxFPS: Int { didSet { defaults.set(maxFPS, forKey: "maxFPS") } }
    var showTicks: Bool { didSet { defaults.set(showTicks, forKey: "showTicks") } }
    var showCondensation: Bool { didSet { defaults.set(showCondensation, forKey: "showCondensation") } }
    var showBubbles: Bool { didSet { defaults.set(showBubbles, forKey: "showBubbles") } }
    var showPercentInMenuBar: Bool { didSet { defaults.set(showPercentInMenuBar, forKey: "showPercentInMenuBar") } }

    // MARK: Widget

    var widgetVisible: Bool { didSet { defaults.set(widgetVisible, forKey: "widgetVisible") } }
    var placement: Placement { didSet { defaults.set(placement.rawValue, forKey: "placement") } }
    var lockPosition: Bool { didSet { defaults.set(lockPosition, forKey: "lockPosition") } }
    var allSpaces: Bool { didSet { defaults.set(allSpaces, forKey: "allSpaces") } }
    var snapToEdges: Bool { didSet { defaults.set(snapToEdges, forKey: "snapToEdges") } }
    var clickAction: ClickAction { didSet { defaults.set(clickAction.rawValue, forKey: "clickAction") } }

    // MARK: Reminders

    var remindersEnabled: Bool { didSet { defaults.set(remindersEnabled, forKey: "remindersEnabled") } }
    var reminderInterval: Int { didSet { defaults.set(reminderInterval, forKey: "reminderInterval") } }
    var smartReminders: Bool { didSet { defaults.set(smartReminders, forKey: "smartReminders") } }
    var reminderSound: Bool { didSet { defaults.set(reminderSound, forKey: "reminderSound") } }
    var nudgeEnabled: Bool { didSet { defaults.set(nudgeEnabled, forKey: "nudgeEnabled") } }
    var snoozedUntil: Date? { didSet { defaults.set(snoozedUntil, forKey: "snoozedUntil") } }

    // MARK: Sound, haptics, keys

    var pourSound: Bool { didSet { defaults.set(pourSound, forKey: "pourSound") } }
    var goalSound: Bool { didSet { defaults.set(goalSound, forKey: "goalSound") } }
    var volume: Double { didSet { defaults.set(volume, forKey: "volume") } }
    var haptics: Bool { didSet { defaults.set(haptics, forKey: "haptics") } }
    var hotKeysEnabled: Bool { didSet { defaults.set(hotKeysEnabled, forKey: "hotKeysEnabled") } }
    var logHotKey: HotKey { didSet { Self.store(logHotKey, "logHotKey", defaults) } }
    var toggleHotKey: HotKey { didSet { Self.store(toggleHotKey, "toggleHotKey", defaults) } }

    // MARK: Refills, caffeine, weekly summary

    var bottleSizeML: Double { didSet { defaults.set(bottleSizeML, forKey: "bottleSizeML") } }
    var showRefills: Bool { didSet { defaults.set(showRefills, forKey: "showRefills") } }
    var caffeineTracking: Bool { didSet { defaults.set(caffeineTracking, forKey: "caffeineTracking") } }
    var caffeineRates: CaffeineRates { didSet { Self.store(caffeineRates, "caffeineRates", defaults) } }
    var caffeineCutoffMinutes: Int { didSet { defaults.set(caffeineCutoffMinutes, forKey: "caffeineCutoffMinutes") } }
    var caffeineLimitMG: Double { didSet { defaults.set(caffeineLimitMG, forKey: "caffeineLimitMG") } }
    var weeklySummary: Bool { didSet { defaults.set(weeklySummary, forKey: "weeklySummary") } }

    // MARK: Weather

    var weatherAdjust: Bool { didSet { defaults.set(weatherAdjust, forKey: "weatherAdjust") } }
    var weatherCity: String { didSet { defaults.set(weatherCity, forKey: "weatherCity") } }
    var weatherLatitude: Double { didSet { defaults.set(weatherLatitude, forKey: "weatherLatitude") } }
    var weatherLongitude: Double { didSet { defaults.set(weatherLongitude, forKey: "weatherLongitude") } }

    // MARK: Bottle life

    var iceMode: IceMode { didSet { defaults.set(iceMode.rawValue, forKey: "iceMode") } }
    var lemonSlice: Bool { didSet { defaults.set(lemonSlice, forKey: "lemonSlice") } }
    var steamEnabled: Bool { didSet { defaults.set(steamEnabled, forKey: "steamEnabled") } }

    // MARK: Quiet times for reminders

    var quietInCalls: Bool { didSet { defaults.set(quietInCalls, forKey: "quietInCalls") } }
    var quietInMeetings: Bool { didSet { defaults.set(quietInMeetings, forKey: "quietInMeetings") } }
    var quietWhenAway: Bool { didSet { defaults.set(quietWhenAway, forKey: "quietWhenAway") } }
    var quietFullScreen: Bool { didSet { defaults.set(quietFullScreen, forKey: "quietFullScreen") } }

    // MARK: Sync and quick log

    var iCloudSync: Bool { didSet { defaults.set(iCloudSync, forKey: "iCloudSync") } }
    var inboxEnabled: Bool { didSet { defaults.set(inboxEnabled, forKey: "inboxEnabled") } }
    var quickLogHotKey: HotKey { didSet { Self.store(quickLogHotKey, "quickLogHotKey", defaults) } }
    var unlockedAchievements: [String: Date] { didSet { Self.store(unlockedAchievements, "unlockedAchievements", defaults) } }

    // MARK: Menu bar, HUD, Focus

    var menuBarIcon: MenuBarIconMode { didSet { defaults.set(menuBarIcon.rawValue, forKey: "menuBarIcon") } }
    var hudEnabled: Bool { didSet { defaults.set(hudEnabled, forKey: "hudEnabled") } }
    /// Set by the Sip Focus filter while a chosen Focus is on.
    var focusQuiet: Bool { didSet { defaults.set(focusQuiet, forKey: "focusQuiet") } }
    var focusCalmMotion: Bool { didSet { defaults.set(focusCalmMotion, forKey: "focusCalmMotion") } }
    /// "main", or a display's name to keep the widget there.
    var widgetDisplay: String { didSet { defaults.set(widgetDisplay, forKey: "widgetDisplay") } }

    // MARK: In the bottle (2.0)

    var timeMarkers: Bool { didSet { defaults.set(timeMarkers, forKey: "timeMarkers") } }
    var companionFish: Bool { didSet { defaults.set(companionFish, forKey: "companionFish") } }
    var companionPlant: Bool { didSet { defaults.set(companionPlant, forKey: "companionPlant") } }
    var livingGlass: Bool { didSet { defaults.set(livingGlass, forKey: "livingGlass") } }
    var seasonalPacks: Bool { didSet { defaults.set(seasonalPacks, forKey: "seasonalPacks") } }
    var playfulWater: Bool { didSet { defaults.set(playfulWater, forKey: "playfulWater") } }
    var pourOutUndo: Bool { didSet { defaults.set(pourOutUndo, forKey: "pourOutUndo") } }
    var nightDim: Bool { didSet { defaults.set(nightDim, forKey: "nightDim") } }
    var celebrationStyle: CelebrationStyle { didSet { defaults.set(celebrationStyle.rawValue, forKey: "celebrationStyle") } }

    // MARK: Coaching

    var coachEnabled: Bool { didSet { defaults.set(coachEnabled, forKey: "coachEnabled") } }
    var dismissedGoalSuggestion: Date? { didSet { defaults.set(dismissedGoalSuggestion, forKey: "dismissedGoalSuggestion") } }
    var caffeineHalfLifeHours: Double { didSet { defaults.set(caffeineHalfLifeHours, forKey: "caffeineHalfLifeHours") } }
    var windDown: Bool { didSet { defaults.set(windDown, forKey: "windDown") } }
    var windDownMinutes: Int { didSet { defaults.set(windDownMinutes, forKey: "windDownMinutes") } }
    var lastCall: Bool { didSet { defaults.set(lastCall, forKey: "lastCall") } }
    var morningGlass: Bool { didSet { defaults.set(morningGlass, forKey: "morningGlass") } }
    var calendarPlanner: Bool { didSet { defaults.set(calendarPlanner, forKey: "calendarPlanner") } }
    var preMeetingNudges: Bool { didSet { defaults.set(preMeetingNudges, forKey: "preMeetingNudges") } }
    var workoutFromCalendar: Bool { didSet { defaults.set(workoutFromCalendar, forKey: "workoutFromCalendar") } }
    var weeklySchedule: WeeklySchedule { didSet { Self.store(weeklySchedule, "weeklySchedule", defaults) } }

    // MARK: Play

    var levelsEnabled: Bool { didSet { defaults.set(levelsEnabled, forKey: "levelsEnabled") } }
    var challengesEnabled: Bool { didSet { defaults.set(challengesEnabled, forKey: "challengesEnabled") } }
    var buddiesEnabled: Bool { didSet { defaults.set(buddiesEnabled, forKey: "buddiesEnabled") } }
    var buddiesFolderPath: String { didSet { defaults.set(buddiesFolderPath, forKey: "buddiesFolderPath") } }
    var buddyName: String { didSet { defaults.set(buddyName, forKey: "buddyName") } }
    var buddyID: UUID { didSet { defaults.set(buddyID.uuidString, forKey: "buddyID") } }
    var recapOffer: Bool { didSet { defaults.set(recapOffer, forKey: "recapOffer") } }
    var lastRecapShown: String { didSet { defaults.set(lastRecapShown, forKey: "lastRecapShown") } }

    // MARK: Data

    var backupsEnabled: Bool { didSet { defaults.set(backupsEnabled, forKey: "backupsEnabled") } }

    // MARK: Lifecycle

    var hasOnboarded: Bool { didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") } }
    var lastSeenVersion: String { didSet { defaults.set(lastSeenVersion, forKey: "lastSeenVersion") } }

    init(defaults: UserDefaults = DebugHooks.defaults) {
        self.defaults = defaults
        let d = defaults
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        dailyGoalML = d.double("dailyGoalML", 2500)
        unit = d.enumValue("unit", .milliliters)
        dayStartHour = d.int("dayStartHour", 4)
        wakeMinutes = d.int("wakeMinutes", 7 * 60)
        sleepMinutes = d.int("sleepMinutes", 23 * 60)
        weightKg = d.double("weightKg", 70)
        exerciseMinutes = d.double("exerciseMinutes", 30)
        hotClimate = d.bool("hotClimate", false)
        streakFreezes = d.bool("streakFreezes", true)

        cups = Self.load("cups", d) ?? Cup.defaults
        defaultCupID = d.string(forKey: "defaultCupID").flatMap(UUID.init(uuidString:))
        factors = Self.load("factors", d) ?? HydrationFactors()
        disabledDrinks = Self.load("disabledDrinks", d) ?? []

        bottleStyle = d.enumValue("bottleStyle", .classic)
        customBottle = Self.load("customBottle", d) ?? CustomBottleSpec()
        bottleLabel = d.string(forKey: "bottleLabel") ?? ""
        glassTint = d.enumValue("glassTint", .clear)
        theme = d.enumValue("theme", .ocean)
        layeredDrinks = d.bool("layeredDrinks", true)
        cardBackground = d.enumValue("cardBackground", CardBackground.systemDefault)
        cardOpacity = d.double("cardOpacity", 1)
        widgetSize = d.enumValue("widgetSize", .medium)
        widgetScale = d.double("widgetScale", 1)
        motion = d.enumValue("motion", reduceMotion ? .minimal : .full)
        maxFPS = d.int("maxFPS", 60)
        showTicks = d.bool("showTicks", true)
        showCondensation = d.bool("showCondensation", true)
        showBubbles = d.bool("showBubbles", true)
        showPercentInMenuBar = d.bool("showPercentInMenuBar", false)

        widgetVisible = d.bool("widgetVisible", true)
        placement = d.enumValue("placement", .desktop)
        lockPosition = d.bool("lockPosition", false)
        allSpaces = d.bool("allSpaces", true)
        snapToEdges = d.bool("snapToEdges", true)
        clickAction = d.enumValue("clickAction", .addDefault)

        remindersEnabled = d.bool("remindersEnabled", false)
        reminderInterval = d.int("reminderInterval", 60)
        smartReminders = d.bool("smartReminders", true)
        reminderSound = d.bool("reminderSound", true)
        nudgeEnabled = d.bool("nudgeEnabled", true)
        snoozedUntil = d.object(forKey: "snoozedUntil") as? Date

        pourSound = d.bool("pourSound", true)
        goalSound = d.bool("goalSound", true)
        volume = d.double("volume", 0.6)
        haptics = d.bool("haptics", true)
        hotKeysEnabled = d.bool("hotKeysEnabled", true)
        logHotKey = Self.load("logHotKey", d) ?? .defaultLog
        toggleHotKey = Self.load("toggleHotKey", d) ?? .defaultToggle

        bottleSizeML = d.double("bottleSizeML", 750)
        showRefills = d.bool("showRefills", true)
        caffeineTracking = d.bool("caffeineTracking", true)
        caffeineRates = Self.load("caffeineRates", d) ?? CaffeineRates()
        caffeineCutoffMinutes = d.int("caffeineCutoffMinutes", 15 * 60)
        caffeineLimitMG = d.double("caffeineLimitMG", 400)
        weeklySummary = d.bool("weeklySummary", true)

        weatherAdjust = d.bool("weatherAdjust", false)
        weatherCity = d.string(forKey: "weatherCity") ?? ""
        weatherLatitude = d.double("weatherLatitude", 0)
        weatherLongitude = d.double("weatherLongitude", 0)

        iceMode = d.enumValue("iceMode", .hotDays)
        lemonSlice = d.bool("lemonSlice", false)
        steamEnabled = d.bool("steamEnabled", true)

        quietInCalls = d.bool("quietInCalls", true)
        quietInMeetings = d.bool("quietInMeetings", false)
        quietWhenAway = d.bool("quietWhenAway", true)
        quietFullScreen = d.bool("quietFullScreen", true)

        iCloudSync = d.bool("iCloudSync", false)
        inboxEnabled = d.bool("inboxEnabled", true)
        quickLogHotKey = Self.load("quickLogHotKey", d) ?? .defaultQuickLog
        unlockedAchievements = Self.load("unlockedAchievements", d) ?? [:]

        menuBarIcon = d.enumValue("menuBarIcon", .always)
        hudEnabled = d.bool("hudEnabled", true)
        focusQuiet = d.bool("focusQuiet", false)
        focusCalmMotion = d.bool("focusCalmMotion", false)
        widgetDisplay = d.string(forKey: "widgetDisplay") ?? "main"

        timeMarkers = d.bool("timeMarkers", true)
        companionFish = d.bool("companionFish", true)
        companionPlant = d.bool("companionPlant", true)
        livingGlass = d.bool("livingGlass", true)
        seasonalPacks = d.bool("seasonalPacks", true)
        playfulWater = d.bool("playfulWater", true)
        pourOutUndo = d.bool("pourOutUndo", true)
        nightDim = d.bool("nightDim", true)
        celebrationStyle = d.enumValue("celebrationStyle", .surprise)

        coachEnabled = d.bool("coachEnabled", true)
        dismissedGoalSuggestion = d.object(forKey: "dismissedGoalSuggestion") as? Date
        caffeineHalfLifeHours = d.double("caffeineHalfLifeHours", 5)
        windDown = d.bool("windDown", true)
        windDownMinutes = d.int("windDownMinutes", 60)
        lastCall = d.bool("lastCall", true)
        morningGlass = d.bool("morningGlass", true)
        calendarPlanner = d.bool("calendarPlanner", false)
        preMeetingNudges = d.bool("preMeetingNudges", false)
        workoutFromCalendar = d.bool("workoutFromCalendar", false)
        weeklySchedule = Self.load("weeklySchedule", d) ?? WeeklySchedule()

        levelsEnabled = d.bool("levelsEnabled", true)
        challengesEnabled = d.bool("challengesEnabled", true)
        buddiesEnabled = d.bool("buddiesEnabled", false)
        buddiesFolderPath = d.string(forKey: "buddiesFolderPath") ?? ""
        buddyName = d.string(forKey: "buddyName") ?? NSFullUserName().components(separatedBy: " ").first ?? "Me"
        if let id = d.string(forKey: "buddyID").flatMap(UUID.init(uuidString:)) {
            buddyID = id
        } else {
            let id = UUID()
            buddyID = id
            d.set(id.uuidString, forKey: "buddyID")
        }
        recapOffer = d.bool("recapOffer", true)
        lastRecapShown = d.string(forKey: "lastRecapShown") ?? ""

        backupsEnabled = d.bool("backupsEnabled", true)

        hasOnboarded = d.bool("hasOnboarded", false)
        lastSeenVersion = d.string(forKey: "lastSeenVersion") ?? ""

        applyDebugOverrides()
    }

    /// Debug hooks change what's shown for this launch only. The property's
    /// `didSet` still writes, so the previously saved value is put back
    /// straight afterwards.
    private func applyDebugOverrides() {
        if let s = DebugHooks.size {
            let size: WidgetSize? = ["s": .small, "m": .medium, "l": .large, "xl": .extraLarge][s.lowercased()] ?? WidgetSize(rawValue: s)
            if let size { withoutPersisting("widgetSize") { widgetSize = size } }
        }
        if let s = DebugHooks.style, let style = BottleStyle(rawValue: s) {
            withoutPersisting("bottleStyle") { bottleStyle = style }
        }
        if let s = DebugHooks.theme, let theme = LiquidTheme(rawValue: s) {
            withoutPersisting("theme") { self.theme = theme }
        }
        if let s = DebugHooks.background, let bg = CardBackground(rawValue: s) {
            withoutPersisting("cardBackground") { cardBackground = bg }
        }
        if DebugHooks.demo { withoutPersisting("hasOnboarded") { hasOnboarded = true } }
    }

    private func withoutPersisting(_ key: String, _ body: () -> Void) {
        let saved = defaults.persistentDomain(forName: DebugHooks.defaultsDomain)?[key]
        body()
        if let saved { defaults.set(saved, forKey: key) } else { defaults.removeObject(forKey: key) }
    }

    // MARK: Derived

    var activeHours: ActiveHours { ActiveHours(wakeMinutes: wakeMinutes, sleepMinutes: sleepMinutes) }

    var defaultCup: Cup {
        cups.first { $0.id == defaultCupID } ?? cups.first { $0.drink == .water && $0.amountML >= 200 } ?? cups.first
            ?? Cup(name: "Glass", amountML: 250, symbol: "cup.and.saucer.fill")
    }

    /// A quick-add cup by name, ignoring case.
    func cup(named name: String) -> Cup? {
        let wanted = name.trimmingCharacters(in: .whitespaces).lowercased()
        return cups.first { $0.name.lowercased() == wanted }
    }

    var enabledDrinks: [DrinkKind] { DrinkKind.allCases.filter { !disabledDrinks.contains($0) } }

    var quickLogCups: [QuickLogCup] { cups.map { QuickLogCup(name: $0.name, ml: $0.amountML, drink: $0.drink) } }

    /// Any feature that reads the calendar is on.
    var usesCalendar: Bool { calendarPlanner || preMeetingNudges || workoutFromCalendar || quietInMeetings }

    var hasWeatherLocation: Bool { !weatherCity.isEmpty && (weatherLatitude != 0 || weatherLongitude != 0) }

    /// Weight × 35 ml, plus 350 ml per 30 minutes of exercise, plus 500 ml in
    /// hot weather, rounded to 50 ml.
    var suggestedGoalML: Double {
        let base = weightKg * 35 + exerciseMinutes / 30 * 350 + (hotClimate ? 500 : 0)
        return (base / 50).rounded() * 50
    }

    func resetAppearance() {
        bottleStyle = .classic
        bottleLabel = ""
        glassTint = .clear
        theme = .ocean
        layeredDrinks = true
        cardBackground = .systemDefault
        cardOpacity = 1
        widgetScale = 1
        motion = .full
        maxFPS = 60
        showTicks = true
        showCondensation = true
        showBubbles = true
        timeMarkers = true
        companionFish = true
        companionPlant = true
        livingGlass = true
        seasonalPacks = true
        playfulWater = true
        nightDim = true
    }

    // MARK: Helpers

    private static func store<T: Encodable>(_ value: T, _ key: String, _ defaults: UserDefaults) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ key: String, _ defaults: UserDefaults) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}

private extension UserDefaults {
    func double(_ key: String, _ fallback: Double) -> Double {
        object(forKey: key) == nil ? fallback : double(forKey: key)
    }

    func int(_ key: String, _ fallback: Int) -> Int {
        object(forKey: key) == nil ? fallback : integer(forKey: key)
    }

    func bool(_ key: String, _ fallback: Bool) -> Bool {
        object(forKey: key) == nil ? fallback : bool(forKey: key)
    }

    func enumValue<E: RawRepresentable>(_ key: String, _ fallback: E) -> E where E.RawValue == String {
        string(forKey: key).flatMap(E.init(rawValue:)) ?? fallback
    }
}
