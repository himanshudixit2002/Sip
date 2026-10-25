import AppKit
import Observation
import SwiftUI
import SipCore

/// Owns the live objects and is the single place actions go through, so a
/// drink logged from the widget, the popover, a hotkey or a notification all
/// animate, sound, reschedule and save the same way.
@MainActor
@Observable
final class AppState {
    static let shared = AppState()

    let settings: SettingsStore
    let store: HydrationStore
    let reminders = Reminders()
    let weather = WeatherService()
    let settingsNav = SettingsNavigation()
    /// Every badge and how close you are to it.
    private(set) var achievements: [AchievementStatus] = []
    /// Level, challenge, coach, score, plan: see `Gameplay.swift`.
    var derived = DerivedStats()

    /// Advances every 30 s so relative times and pace stay current.
    private(set) var now = Date()
    private(set) var toast: Toast?
    /// True while the bottle is wobbling for attention.
    private(set) var isNudging = false

    @ObservationIgnored let sounds = Sounds()
    @ObservationIgnored let hotKeys = HotKeys()
    @ObservationIgnored private(set) var widget: WidgetController?
    @ObservationIgnored private var statusItem: StatusItemController?
    @ObservationIgnored private(set) var popover: PopoverController?
    @ObservationIgnored private(set) lazy var hud = HUDController(state: self)
    /// The menu bar icon is shown just while the popover needs an anchor.
    @ObservationIgnored private var statusItemBorrowed = false
    @ObservationIgnored private var settingsWindow: HostedWindow?
    @ObservationIgnored private var insightsWindow: HostedWindow?
    @ObservationIgnored private var onboardingWindow: HostedWindow?
    @ObservationIgnored private var clockTimer: Timer?
    @ObservationIgnored private var dayTimer: Timer?
    @ObservationIgnored private var toastEnd = Debouncer()
    @ObservationIgnored private var lastNudge: Date?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored let quiet = QuietTimes()
    @ObservationIgnored private var quickLog: QuickLogController?
    @ObservationIgnored private var folderWatcher: FolderWatcher?
    @ObservationIgnored private(set) var lastReminderShown: Date?
    @ObservationIgnored let calendar = CalendarService()
    @ObservationIgnored var statusDebounce = Debouncer()
    @ObservationIgnored private var pendingReminderKind: ReminderKind = .regular
    @ObservationIgnored private var derivedDebounce = Debouncer()
    @ObservationIgnored private(set) lazy var buddies = BuddiesService(state: self)
    @ObservationIgnored private let widgetBridge = WidgetBridge()
    @ObservationIgnored var recapWindow: HostedWindow?
    @ObservationIgnored var whatsNewWindow: HostedWindow?
    @ObservationIgnored private var weeklyDebounce = Debouncer()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var pendingURLs: [URL] = []

    private init() {
        settings = SettingsStore()
        store = HydrationStore(settings: settings, demo: DebugHooks.demo)
    }

    // MARK: - Lifecycle

    func start() {
        sounds.volume = Float(settings.volume)
        store.onChange = { [weak self] in self?.storeChanged() }
        quiet.inMeeting = { [weak self] in
            guard let self else { return false }
            return self.calendar.inMeeting(dayStart: self.store.clock.start(of: self.store.today),
                                           dayEnd: self.store.clock.end(of: self.store.today))
        }
        calendar.onChange = { [weak self] in self?.calendarChanged() }
        if settings.usesCalendar { calendar.startWatching() }
        applyWorkoutDay()
        recomputeDerived(announce: false)
        updateAchievements(announce: false)

        statusItem = StatusItemController(state: self)
        let popover = PopoverController(state: self)
        popover.onClose = { [weak self] in self?.popoverClosed() }
        self.popover = popover
        let widget = WidgetController(state: self)
        self.widget = widget
        if settings.widgetVisible { widget.show() }
        updateStatusItem()

        reminders.onLog = { [weak self] in
            guard let self else { return }
            SipCommand.logDefault.perform(self, source: .notification)
        }
        reminders.onSnooze = { [weak self] in self?.snooze() }
        reminders.onOpen = { [weak self] in self?.showPopover() }
        reminders.onRoute = { [weak self] route in self?.openRoute(route) }
        reminders.onDue = { [weak self] in self?.reminderDue() }
        reminders.start(logLabel: logActionLabel)
        weather.onUpdate = { [weak self] in self?.applyWeather() }

        hotKeys.onAction = { [weak self] action in
            guard let self else { return }
            switch action {
            case .logDefault: SipCommand.logDefault.perform(self, source: .hotkey)
            case .toggleWidget: self.peekOrToggle()
            case .quickLog: SipCommand.quickLog.perform(self, source: .hotkey)
            }
        }
        applyHotKeys()

        startClock()
        startAwayWatch()
        scheduleDayRollover()
        watchSettings()
        rescheduleReminder()
        refreshWeather()
        setUpSync()
        scheduleWeeklySummary()

        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshAfterWake() }
        })

        runDebugHooks()
        dailyHousekeeping()
        widgetBridge.update(from: self)
        buddies.start()
        writeStatusSoon()
        started = true
        pendingURLs.forEach(handle)
        pendingURLs.removeAll()
        if !settings.hasOnboarded {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) { [weak self] in self?.showOnboarding() }
        } else if settings.lastSeenVersion != Self.version, !DebugHooks.demo {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.showWhatsNew() }
        }
        if !settings.hasOnboarded { settings.lastSeenVersion = Self.version }
    }

    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "2.0" }

    // MARK: - Logging

    /// Every drink goes through here, wherever it was logged from, so they
    /// all animate, sound, toast, celebrate and reschedule the same way.
    /// `date` logs to an earlier time (or day) without the pour animation.
    func log(ml: Double, drink: DrinkKind, source: LogSource, at date: Date? = nil) {
        guard ml > 0 else { return }
        if let date, store.clock.key(for: date) != store.today || date < Date().addingTimeInterval(-15 * 60) {
            store.add(ml: ml, drink: drink, at: date)
            let day = store.clock.key(for: date) == store.today ? "earlier today"
                : date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            showToast(Toast(icon: "clock.arrow.circlepath", text: "+\(Volume.format(ml, settings.unit)) \(day)",
                            tint: settings.theme.color(for: drink)), duration: 2)
            rescheduleReminder()
            return
        }
        let goal = store.goal
        let before = store.consumed
        let effective = ml * settings.factors[drink]
        // The bottles start their pour before the level changes, so the water
        // rises with the droplets instead of jumping first.
        SipEvents.pour(fraction: effective / goal, drink: drink)
        let streakBefore = store.streak
        store.add(ml: ml, drink: drink)
        let after = store.consumed

        if settings.pourSound { sounds.playPour(fraction: effective / goal) }
        if settings.haptics { Haptics.levelChange() }
        isNudging = false

        if before < goal - 0.5, after >= goal - 0.5 {
            // Celebrate once the pour has landed.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                self?.celebrateGoal(streakBefore: streakBefore)
            }
        } else if let warning = caffeineWarning(for: store.lastEntry) {
            showToast(warning, duration: 3.5)
        } else {
            showToast(Toast(icon: drink.symbol, text: "+\(Volume.format(ml, settings.unit)) \(drink.title.lowercased())",
                            tint: settings.theme.color(for: drink)), duration: 1.6)
        }
        feedbackIfUnseen(source: source, ml: ml, drink: drink)
        rescheduleReminder()
    }

    func log(cup: Cup, source: LogSource) {
        log(ml: cup.amountML, drink: cup.drink, source: source)
    }

    /// A typed or dragged amount: rounded to a tidy step in your unit, the
    /// same way wherever it was entered.
    func logAmount(_ ml: Double, drink: DrinkKind, source: LogSource, at date: Date? = nil) {
        log(ml: Volume.snap(ml, settings.unit), drink: drink, source: source, at: date)
    }

    /// Dragging up on a bottle.
    func pour(ml: Double, source: LogSource) {
        logAmount(ml, drink: settings.defaultCup.drink, source: source)
    }

    /// Anything the quick-log box understands ("330 tea", "2 glasses").
    /// Returns false, with a beep, when it can't be read.
    @discardableResult
    func logParsed(_ text: String, source: LogSource) -> Bool {
        guard let parsed = QuickLogParser.parse(text, cups: settings.quickLogCups, unit: settings.unit) else {
            NSSound.beep()
            return false
        }
        logAmount(parsed.ml, drink: parsed.drink ?? settings.defaultCup.drink, source: source)
        return true
    }

    /// Logs one full bottle of your bottle size.
    func logRefill(source: LogSource) {
        log(ml: settings.bottleSizeML, drink: .water, source: source)
    }

    /// The widget can't be seen (hidden or buried under windows) and the
    /// drink came from elsewhere: show the HUD so it doesn't vanish silently.
    private func feedbackIfUnseen(source: LogSource, ml: Double, drink: DrinkKind) {
        guard source.isRemote, !(widget?.isOnScreen ?? false) else { return }
        hud.show(ml: ml, drink: drink)
    }

    var refill: RefillProgress {
        RefillProgress(bottleML: settings.bottleSizeML, consumedML: store.consumed, goalML: store.goal)
    }

    var caffeineToday: Double {
        settings.caffeineTracking ? settings.caffeineRates.milligrams(in: store.todayEntries) : 0
    }

    private func caffeineWarning(for entry: Entry?) -> Toast? {
        guard settings.caffeineTracking, let entry else { return nil }
        switch Caffeine.check(entry: entry, todayEntries: store.todayEntries, rates: settings.caffeineRates,
                              cutoffMinutes: settings.caffeineCutoffMinutes, limitMG: settings.caffeineLimitMG,
                              calendar: .current) {
        case .fine:
            return nil
        case .afterCutoff:
            return Toast(icon: "moon.zzz.fill", text: "Caffeine this late can cost you sleep", tint: Palette.caffeine)
        case .overLimit(let mg):
            return Toast(icon: "exclamationmark.triangle.fill", text: "\(Int(mg)) mg of caffeine today",
                         tint: Palette.warning)
        }
    }

    /// Ice on hot days, an optional lemon, steam for a while after tea or coffee.
    var bottleExtras: BottleExtras {
        let ice: Int
        switch settings.iceMode {
        case .never: ice = 0
        case .always: ice = 3
        case .hotDays: ice = (weather.maxTemperatureC ?? 0) >= 28 ? 3 : 0
        }
        let steam = settings.steamEnabled && (store.todayEntries.last.map {
            ($0.drink == .tea || $0.drink == .coffee) && now.timeIntervalSince($0.date) < 15 * 60
        } ?? false)
        return BottleExtras(iceCubes: ice, lemon: settings.lemonSlice, steam: steam)
    }

    // MARK: - Store changes

    private func storeChanged() {
        statusItem?.refresh()
        recomputeDerived(announce: true)
        updateAchievements(announce: true)
        writeStatusSoon()
        buddies.publishSoon()
        widgetBridge.update(from: self)
        // The weekly summary's numbers change with every drink; reschedule it
        // once things settle rather than on every change.
        weeklyDebounce.schedule(after: 5) { [weak self] in self?.scheduleWeeklySummary() }
    }

    /// History was erased or imported wholesale: everything that depends on
    /// it starts over.
    func historyReplaced() {
        store.recompute()
        SipEvents.post(SipEvents.drain)
        rescheduleReminder()
        updateAchievements(announce: false)
    }

    private func updateAchievements(announce: Bool) {
        let started = CFAbsoluteTimeGetCurrent()
        defer {
            if DebugHooks.has("timing") {
                print(String(format: "achievements: %.1f ms", (CFAbsoluteTimeGetCurrent() - started) * 1000)); fflush(stdout)
            }
        }
        var temperatures: [DayKey: Double] = [:]
        if let high = weather.maxTemperatureC { temperatures[store.today] = high }
        let list = Achievements.evaluate(.init(history: store.history, summaries: store.summaries,
                                               bestStreak: store.streak.best, clock: store.clock,
                                               bottleML: settings.bottleSizeML, factors: settings.factors,
                                               maxTemperatureByDay: temperatures,
                                               challengeDays: derived.completedChallengeDays,
                                               repairedDays: store.repairs, level: derived.level.level))
        achievements = list
        guard !DebugHooks.demo else { return }
        var known = settings.unlockedAchievements
        let fresh = list.filter { $0.unlocked && known[$0.id] == nil }
        guard !fresh.isEmpty else { return }
        for badge in fresh { known[badge.id] = Date() }
        settings.unlockedAchievements = known
        guard announce, let first = fresh.first else { return }
        // After the drink's own toast.
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.showToast(Toast(icon: first.symbol, text: "Badge unlocked: \(first.title)", tint: Palette.badge), duration: 4)
            if self?.settings.goalSound == true { self?.sounds.playChime() }
        }
    }

    // MARK: - Quick log and links

    func toggleQuickLog() {
        if quickLog == nil { quickLog = QuickLogController(state: self) }
        quickLog?.toggle()
    }

    func handle(_ url: URL) {
        // A link that launched Sip arrives before it has finished starting.
        guard started else { pendingURLs.append(url); return }
        guard let action = URLAction(url) else { return }
        switch action {
        case .log(let ml, let drink):
            logAmount(ml, drink: drink ?? settings.defaultCup.drink, source: .url)
        case .logText(let text):
            logParsed(text, source: .url)
        case .logCup(let name):
            if name.isEmpty {
                SipCommand.logDefault.perform(self, source: .url)
            } else if let cup = settings.cup(named: name) {
                log(cup: cup, source: .url)
            } else {
                NSSound.beep()
                showToast(Toast(icon: "questionmark.circle", text: "No cup called “\(name)”", tint: Palette.warning), duration: 3)
            }
        case .command(let command):
            command.perform(self, source: .url)
        case .widget(let visible):
            settings.widgetVisible = visible ?? !settings.widgetVisible
        }
    }

    // MARK: - Weather

    func refreshWeather(force: Bool = false) {
        // Fetched for the goal bonus, the weather on the glass, or both.
        guard settings.weatherAdjust || settings.livingGlass, settings.hasWeatherLocation else {
            // Forget the old reading too, or ice keeps showing for a hot day.
            weather.clear()
            store.setGoalBonus(0)
            return
        }
        weather.refreshIfNeeded(latitude: settings.weatherLatitude, longitude: settings.weatherLongitude,
                                today: store.today, force: force)
    }

    private func applyWeather() {
        store.setGoalBonus(settings.weatherAdjust && settings.hasWeatherLocation ? weather.bonusML : 0)
        rescheduleReminder()
    }

    // MARK: - Sync and inbox

    private func setUpSync() {
        folderWatcher?.stop()
        folderWatcher = nil
        guard !DebugHooks.demo else { return }
        var folders: [URL] = []
        if settings.iCloudSync { folders.append(store.fileURL.deletingLastPathComponent()) }
        if settings.inboxEnabled {
            folders += SipPaths.inboxFiles(iCloud: settings.iCloudSync).map { $0.deletingLastPathComponent() }
        }
        guard !folders.isEmpty else { return }
        let watcher = FolderWatcher { [weak self] in self?.syncFoldersChanged() }
        watcher.watch(folders)
        folderWatcher = watcher
        syncFoldersChanged()
    }

    private func syncFoldersChanged() {
        if settings.iCloudSync { store.reloadIfChangedOnDisk() }
        if settings.inboxEnabled { importInbox() }
    }

    /// Logs whatever an iPhone Shortcut (or anything else) appended to an
    /// inbox file, then empties it.
    private func importInbox() {
        var logged: [Entry] = []
        for file in SipPaths.inboxFiles(iCloud: settings.iCloudSync) {
            guard let text = try? String(contentsOf: file, encoding: .utf8),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            try? "".write(to: file, atomically: true, encoding: .utf8)
            logged += Inbox.parse(text, now: Date(), cups: settings.quickLogCups, unit: settings.unit).entries
        }
        guard !logged.isEmpty else { return }
        let total = logged.reduce(0) { $0 + $1.amountML }
        if logged.count == 1, let one = logged.first, abs(one.date.timeIntervalSinceNow) < 120 {
            log(ml: one.amountML, drink: one.drink, source: .inbox)
        } else {
            store.importEntries(logged)
            SipEvents.post(SipEvents.wobble)
            rescheduleReminder()
        }
        showToast(Toast(icon: "iphone", text: "Logged \(Volume.format(total, settings.unit)) from your inbox",
                        tint: settings.theme.surface), duration: 3)
    }

    // MARK: - Weekly summary

    /// Next Sunday at 19:00 (or today, if it's Sunday and earlier than that),
    /// with this week's numbers.
    private func scheduleWeeklySummary() {
        guard settings.weeklySummary else {
            reminders.scheduleWeekly(at: nil, title: "", body: "")
            return
        }
        let calendar = Calendar.current
        var parts = DateComponents()
        parts.weekday = 1
        parts.hour = 19
        guard let date = calendar.nextDate(after: Date(), matching: parts, matchingPolicy: .nextTime) else { return }
        let lastDay = store.clock.key(for: date)
        let summary = WeeklySummary(summaries: store.summaries, last: lastDay, streak: store.streak.current)
        let text = summary.text(unit: settings.unit)
        reminders.scheduleWeekly(at: date, title: text.title, body: text.body)
    }

    private func celebrateGoal(streakBefore: StreakResult) {
        let streak = store.streak
        let milestone = streak.milestone.map { streak.current == $0 && streakBefore.current < $0 } ?? false
        SipEvents.post(SipEvents.celebrate, ["style": celebrationStyle(milestone: milestone).rawValue])
        if settings.goalSound { sounds.playChime() }
        if let milestone = streak.milestone, streak.current == milestone, streakBefore.current < milestone {
            let tier = FlameTier(streak: milestone)
            showToast(Toast(icon: "flame.fill", text: "\(milestone)-day streak! \(tier.name)",
                            tint: tier.colors.dropFirst().first ?? .orange), duration: 4)
        } else if streak.freezesBanked > streakBefore.freezesBanked {
            showToast(Toast(icon: "snowflake", text: "Goal reached · streak freeze earned", tint: Palette.freeze), duration: 4)
        } else {
            showToast(Toast(icon: "checkmark.seal.fill",
                            text: streak.current > 1 ? "Goal reached · \(streak.current)-day streak" : "Goal reached!",
                            tint: Palette.goal), duration: 4)
        }
    }

    func undo(source: LogSource) {
        guard let entry = store.todayEntries.last else { return }
        delete(entry, source: source)
    }

    /// Undo and delete behave the same: the water drains, a bloop, a toast.
    func delete(_ entry: Entry, source: LogSource) {
        store.delete(entry.id)
        if store.clock.key(for: entry.date) == store.today { SipEvents.post(SipEvents.drain) }
        if settings.pourSound { sounds.playBloop() }
        showToast(Toast(icon: "arrow.uturn.backward", text: "Removed \(Volume.format(entry.amountML, settings.unit))"), duration: 1.6)
        if source.isRemote, !(widget?.isOnScreen ?? false) {
            hud.show(ml: -entry.amountML, drink: entry.drink)
        }
        rescheduleReminder()
    }

    func bottleTapped(source: LogSource) {
        switch settings.clickAction {
        case .addDefault: SipCommand.logDefault.perform(self, source: source)
        case .openPopover: togglePopover(anchor: source == .popover ? .statusItem : .widget)
        }
    }

    // MARK: - Toasts

    func showToast(_ toast: Toast, duration: Double) {
        self.toast = toast
        toastEnd.schedule(after: duration) { [weak self] in self?.toast = nil }
    }

    // MARK: - Widget, popover, menu bar

    /// The ⌃⌥⇧W hotkey: bring a buried widget forward; otherwise show or hide it.
    func peekOrToggle() {
        guard let widget, settings.widgetVisible else {
            settings.widgetVisible = true
            return
        }
        if widget.isOnScreen && !widget.peeking {
            settings.widgetVisible = false
        } else if widget.peeking {
            widget.endPeek()
        } else {
            widget.peek()
        }
    }

    func peek() {
        if !settings.widgetVisible { settings.widgetVisible = true }
        widget?.peek()
    }

    /// Sip was opened again from Spotlight, Launchpad, Finder or the Dock
    /// while running. Settings is the nearest thing it has to a main window,
    /// and what people opening an app expect to see.
    func reopened() {
        if !settings.hasOnboarded { showOnboarding(); return }
        openSettings()
    }

    /// The ⋯ button on the widget.
    func showWidgetMenu() { widget?.showMenu() }

    func togglePopover(anchor: PopoverAnchor = .automatic) {
        if popover?.isShown == true { popover?.close() } else { showPopover(anchor: anchor) }
    }

    func showPopover(anchor: PopoverAnchor = .automatic, focusCustom: Bool = false) {
        guard let popover else { return }
        popover.presence.focusCustom = focusCustom
        if popover.isShown { return }
        let useWidget: Bool
        switch anchor {
        case .widget: useWidget = settings.widgetVisible
        case .statusItem: useWidget = !(statusItem?.isVisible ?? false) && settings.widgetVisible
        case .automatic: useWidget = settings.widgetVisible
        }
        if useWidget, let widget {
            // Lift the card above other windows while the popover is open, or
            // it could appear over a widget you can't see.
            widget.peek(seconds: nil)
            let frame = widget.cardScreenRect
            let screen = widget.panel.screen
            let lowOnScreen = frame.midY < (screen?.visibleFrame.midY ?? 0)
            popover.show(below: frame, above: lowOnScreen, screen: screen)
            return
        }
        if !(statusItem?.isVisible ?? false) {
            statusItemBorrowed = true
            statusItem?.setVisible(true)
        }
        if let button = statusItem?.button, let window = button.window {
            let icon = window.convertToScreen(button.convert(button.bounds, to: nil))
            popover.show(below: icon, above: false, screen: window.screen ?? NSScreen.main)
        }
    }

    private func popoverClosed() {
        widget?.endPeek()
        if statusItemBorrowed {
            statusItemBorrowed = false
            updateStatusItem()
        }
    }

    /// Always by default. "Only when the widget is hidden" still guarantees a
    /// way back in.
    func updateStatusItem() {
        let visible: Bool
        switch settings.menuBarIcon {
        case .always: visible = true
        case .never: visible = false
        case .automatic: visible = !settings.widgetVisible
        }
        statusItem?.setVisible(visible || statusItemBorrowed)
    }

    // MARK: - Windows

    func openSettings(tab: SettingsTab? = nil) {
        if let tab { settingsNav.tab = tab }
        present(&settingsWindow, title: "Sip Settings", size: NSSize(width: 820, height: 620)) {
            SettingsView(state: self, nav: self.settingsNav)
        }
    }

    func openInsights() {
        present(&insightsWindow, title: "Sip Insights", size: NSSize(width: 900, height: 780)) {
            InsightsView(state: self)
        }
    }

    func showOnboarding() {
        present(&onboardingWindow, title: "Welcome to Sip", size: NSSize(width: 560, height: 620), resizable: false) {
            OnboardingView(state: self)
        }
    }

    /// Opens a window, creating it on first use. Closing it frees the whole
    /// view tree rather than keeping it around hidden.
    func present<V: View>(_ slot: inout HostedWindow?, title: String, size: NSSize, resizable: Bool = true,
                                  content: () -> V) {
        if slot == nil {
            let window = HostedWindow(title: title, size: size, content: content(), resizable: resizable)
            let id = ObjectIdentifier(window)
            window.onClose = { [weak self] in self?.windowClosed(id) }
            slot = window
        }
        setActsAsApp(true)
        slot?.present()
    }

    /// While one of its windows is open Sip acts like a normal app: a Dock
    /// icon, a place in ⌘-Tab and its menus in the menu bar. Once they're all
    /// closed it goes back to being just the widget and the menu bar icon.
    private func setActsAsApp(_ app: Bool) {
        let policy: NSApplication.ActivationPolicy = app ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    private var hasOpenWindows: Bool {
        [settingsWindow, insightsWindow, onboardingWindow, recapWindow, whatsNewWindow].contains { $0 != nil }
    }

    private func windowClosed(_ id: ObjectIdentifier) {
        if settingsWindow.map(ObjectIdentifier.init) == id { settingsWindow = nil }
        if insightsWindow.map(ObjectIdentifier.init) == id { insightsWindow = nil }
        if onboardingWindow.map(ObjectIdentifier.init) == id { onboardingWindow = nil }
        if recapWindow.map(ObjectIdentifier.init) == id { recapWindow = nil }
        if whatsNewWindow.map(ObjectIdentifier.init) == id { whatsNewWindow = nil }
        if !hasOpenWindows { setActsAsApp(false) }
    }

    func finishOnboarding() {
        settings.hasOnboarded = true
        onboardingWindow?.close()
        SipEvents.post(SipEvents.wobble)
    }

    // MARK: - Reminders

    private var logActionLabel: String { "Log \(Volume.format(settings.defaultCup.amountML, settings.unit))" }

    func rescheduleReminder() {
        let next = nextReminder(now: Date())
        pendingReminderKind = next?.kind ?? .regular
        reminders.schedule(at: next?.date)
        writeStatusSoon()
    }

    /// A reminder is due. Hold it while you're on a call, in a meeting, away,
    /// presenting or in a Focus, and try again a few minutes later.
    private func reminderDue() {
        if let reason = quiet.reason(settings: settings) {
            reminders.schedule(at: Date().addingTimeInterval(5 * 60), waiting: reason.rawValue)
            return
        }
        let content = reminderText(kind: pendingReminderKind, at: Date())
        reminders.deliver(title: content.title, body: content.body, sound: settings.reminderSound)
        lastReminderShown = Date()
        rescheduleReminder()
    }

    func reminderContent(at date: Date) -> (title: String, body: String) {
        let sameDay = store.clock.key(for: date) == store.today
        return ReminderCopy.make(consumed: sameDay ? store.consumed : 0, goal: store.goal, unit: settings.unit,
                                 lastSip: store.lastSip, now: date,
                                 expectedFraction: sameDay ? store.expectedFraction(at: date) : 0,
                                 cupLabel: settings.defaultCup.name == "Glass" ? "A glass" : "A \(settings.defaultCup.name.lowercased())")
    }

    func sendTestReminder() {
        let content = reminderContent(at: Date())
        reminders.sendTest(title: content.title, body: content.body, sound: settings.reminderSound)
    }

    private func snooze() {
        settings.snoozedUntil = Date().addingTimeInterval(15 * 60)
        rescheduleReminder()
    }

    // MARK: - Hotkeys

    func applyHotKeys() {
        if settings.hotKeysEnabled {
            hotKeys.register([(.logDefault, settings.logHotKey), (.toggleWidget, settings.toggleHotKey),
                              (.quickLog, settings.quickLogHotKey)])
        } else {
            hotKeys.unregister()
        }
    }

    // MARK: - Clock, day rollover, nudges

    private func startClock() {
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        timer.tolerance = 5
        RunLoop.main.add(timer, forMode: .common)
        clockTimer = timer
    }

    private func tick() {
        now = Date()
        checkNudge()
        // The weather on the glass changes by the hour; nothing to fetch.
    }

    /// Polls how long since the last keyboard or mouse input; no permission is
    /// needed for this. Coming back is caught within a few seconds.
    private func startAwayWatch() {
        let timer = Timer(timeInterval: 4, repeats: true) { _ in
            MainActor.assumeIsolated {
                let away = QuietTimes.idleSeconds() > 90
                if AnimationPolicy.shared.userAway != away { AnimationPolicy.shared.userAway = away }
            }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
    }

    private func checkNudge() {
        guard settings.nudgeEnabled, settings.widgetVisible else { isNudging = false; return }
        guard case .behind = store.pace(at: now) else { isNudging = false; return }
        let window = settings.activeHours.window(on: store.today, clock: store.clock)
        guard now > window.wake, now < window.sleep else { isNudging = false; return }
        let since = now.timeIntervalSince(max(store.lastSip ?? window.wake, window.wake))
        guard since >= Double(settings.reminderInterval * 60) else { isNudging = false; return }
        isNudging = true
        if lastNudge.map({ now.timeIntervalSince($0) > 4 * 60 }) ?? true {
            lastNudge = now
            SipEvents.post(SipEvents.wobble)
        }
    }

    private func scheduleDayRollover() {
        dayTimer?.invalidate()
        let boundary = store.clock.nextBoundary(after: Date()).addingTimeInterval(1)
        let timer = Timer(fire: boundary, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dayRolledOver() }
        }
        RunLoop.main.add(timer, forMode: .common)
        dayTimer = timer
    }

    private func dayRolledOver() {
        applyWorkoutDay()
        store.recompute()
        dailyHousekeeping()
        refreshWeather()
        settings.snoozedUntil = nil
        now = Date()
        SipEvents.post(SipEvents.drain)
        rescheduleReminder()
        scheduleDayRollover()
    }

    private func refreshAfterWake() {
        let previous = store.today
        applyWorkoutDay()
        store.recompute()
        if store.today != previous { dailyHousekeeping() }
        refreshWeather()
        syncFoldersChanged()
        now = Date()
        if store.today != previous { SipEvents.post(SipEvents.drain) }
        rescheduleReminder()
        scheduleDayRollover()
    }

    // MARK: - Reacting to settings

    /// Re-arms itself after each change: `withObservationTracking` fires once.
    private func watch(_ read: @escaping () -> Void, _ action: @escaping () -> Void) {
        withObservationTracking(read) { [weak self] in
            DispatchQueue.main.async {
                guard let self else { return }
                action()
                self.watch(read, action)
            }
        }
    }

    private func watchSettings() {
        let s = settings
        watch({ _ = (s.dailyGoalML, s.weeklySchedule) }) { [weak self] in
            self?.applyWorkoutDay()
            self?.store.goalChanged()
            self?.rescheduleReminder()
        }
        watch({ _ = (s.wakeMinutes, s.sleepMinutes, s.unit, s.coachEnabled, s.challengesEnabled, s.timeMarkers,
                     s.calendarPlanner, s.caffeineTracking, s.caffeineLimitMG, s.levelsEnabled) }) { [weak self] in
            self?.recomputeDerived(announce: false)
        }
        watch({ _ = (s.calendarPlanner, s.preMeetingNudges, s.workoutFromCalendar, s.quietInMeetings) }) { [weak self] in
            guard let self else { return }
            if self.settings.usesCalendar { self.calendar.startWatching() }
            self.applyWorkoutDay()
            self.recomputeDerived(announce: false)
            self.rescheduleReminder()
        }
        watch({ _ = (s.windDown, s.windDownMinutes, s.lastCall, s.morningGlass, s.focusQuiet) }) { [weak self] in
            self?.rescheduleReminder()
        }
        watch({ _ = (s.buddiesEnabled, s.buddiesFolderPath, s.buddyName) }) { [weak self] in self?.buddies.start() }
        watch({ _ = (s.dayStartHour, s.factors, s.streakFreezes) }) { [weak self] in
            self?.store.recompute()
            self?.scheduleDayRollover()
        }
        watch({ _ = (s.widgetSize, s.widgetScale) }) { [weak self] in self?.widget?.applySize() }
        watch({ _ = (s.placement, s.allSpaces, s.lockPosition) }) { [weak self] in self?.widget?.applySettings(resize: false) }
        watch({ _ = s.widgetVisible }) { [weak self] in
            guard let self else { return }
            self.widget?.setVisible(self.settings.widgetVisible)
            self.updateStatusItem()
        }
        watch({ _ = s.menuBarIcon }) { [weak self] in self?.updateStatusItem() }
        watch({ _ = (s.remindersEnabled, s.reminderInterval, s.smartReminders, s.reminderSound,
                     s.wakeMinutes, s.sleepMinutes, s.snoozedUntil) }) { [weak self] in self?.rescheduleReminder() }
        watch({ _ = (s.cups, s.defaultCupID, s.unit) }) { [weak self] in
            guard let self else { return }
            self.reminders.registerCategory(logLabel: self.logActionLabel)
        }
        watch({ _ = (s.hotKeysEnabled, s.logHotKey, s.toggleHotKey, s.quickLogHotKey) }) { [weak self] in self?.applyHotKeys() }
        watch({ _ = (s.weatherAdjust, s.livingGlass, s.weatherLatitude, s.weatherLongitude) }) { [weak self] in
            self?.refreshWeather(force: true)
        }
        watch({ _ = s.iCloudSync }) { [weak self] in
            guard let self else { return }
            self.store.relocate(iCloud: self.settings.iCloudSync)
            self.setUpSync()
        }
        watch({ _ = s.inboxEnabled }) { [weak self] in self?.setUpSync() }
        watch({ _ = (s.weeklySummary, s.unit) }) { [weak self] in self?.scheduleWeeklySummary() }
        watch({ _ = s.bottleSizeML }) { [weak self] in self?.updateAchievements(announce: false) }
        watch({ _ = s.volume }) { [weak self] in
            guard let self else { return }
            self.sounds.volume = Float(self.settings.volume)
        }
        watch({ _ = (s.showPercentInMenuBar, s.unit) }) { [weak self] in self?.statusItem?.refresh() }
        watch({ _ = (s.theme, s.unit, s.cups) }) { [weak self] in
            guard let self else { return }
            self.widgetBridge.update(from: self)
        }
    }

    // MARK: - Debug hooks

    private func runDebugHooks() {
        if DebugHooks.autoPour {
            let timer = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let cup = self.settings.cups.randomElement() ?? self.settings.defaultCup
                    self.log(cup: cup, source: .debug)
                }
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        if DebugHooks.celebrate {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.celebrateGoal(streakBefore: .zero)
            }
        }
        if let tab = DebugHooks.settingsTab {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                self?.openSettings(tab: SettingsTab(rawValue: tab))
            }
        }
        if DebugHooks.insights {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.openInsights() }
        }
        if DebugHooks.popover {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showPopover() }
        }
        if DebugHooks.has("recap") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showRecap() }
        }
        if DebugHooks.has("whatsnew") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showWhatsNew() }
        }
        if DebugHooks.has("hud") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.hud.show(ml: 330, drink: .tea) }
        }
        if DebugHooks.onboarding {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.showOnboarding() }
        }
        if DebugHooks.diagnostics {
            for delay in [2.0, 6.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self else { return }
                    print(self.widget?.diagnostics() ?? "widget: none")
                    print("store: today=\(self.store.today) consumed=\(Int(self.store.consumed)) goal=\(Int(self.store.goal)) " +
                          "streak=\(self.store.streak.current) best=\(self.store.streak.best) " +
                          "freezes=\(self.store.streak.freezesBanked) file=\(self.store.fileURL.path)")
                    print("reminders: auth=\(self.reminders.authorization.rawValue) next=\(self.reminders.nextFire.map { "\($0)" } ?? "none")")
                    fflush(stdout)
                }
            }
        }
        if DebugHooks.bench { Bench.start() }
        if let text = DebugHooks.value("quicklog") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self else { return }
                if self.quickLog == nil { self.quickLog = QuickLogController(state: self) }
                self.quickLog?.preview(text: text.replacingOccurrences(of: "_", with: " "))
            }
        }
        if DebugHooks.has("sharecard"), let folder = DebugHooks.dataDirectory {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
                guard let self, let data = ShareCardView.pngData(state: self) else { return }
                try? data.write(to: folder.appendingPathComponent("sharecard.png"))
                print("sharecard: written"); fflush(stdout)
            }
        }
        if let value = DebugHooks.value("loginitem") {
            let error = LoginItem.set(value != "off")
            print("loginitem: \(error ?? "ok") — \(LoginItem.statusText) [\(Bundle.main.bundlePath)]")
            fflush(stdout)
        }
    }
}
