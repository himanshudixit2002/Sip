import AppIntents
import SipCore

// Siri, Shortcuts, Spotlight and Focus. Each intent runs inside the running
// app and goes through the same command or logging path as a click, so a
// drink logged by voice pours, sounds and shows the HUD like any other.

/// The drinks, for Shortcuts and Siri.
enum DrinkChoice: String, AppEnum {
    case water, sparkling, tea, coffee, milk, juice, electrolyte

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Drink"
    static let caseDisplayRepresentations: [DrinkChoice: DisplayRepresentation] = [
        .water: "Water", .sparkling: "Sparkling water", .tea: "Tea", .coffee: "Coffee",
        .milk: "Milk", .juice: "Juice", .electrolyte: "Electrolyte drink",
    ]

    var kind: DrinkKind { DrinkKind(rawValue: rawValue) ?? .water }
}

enum AmountUnit: String, AppEnum {
    case milliliters, fluidOunces, litres

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Unit"
    static let caseDisplayRepresentations: [AmountUnit: DisplayRepresentation] = [
        .milliliters: "ml", .fluidOunces: "fl oz", .litres: "litres",
    ]

    func milliliters(_ value: Double) -> Double {
        switch self {
        case .milliliters: return value
        case .fluidOunces: return Volume.fromDisplay(value, .fluidOunces)
        case .litres: return value * 1000
        }
    }
}

/// One of your quick-add cups.
struct CupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Cup"
    static let defaultQuery = CupQuery()

    var id: UUID
    var name: String
    var amountML: Double

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(Int(amountML)) ml")
    }
}

struct CupQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [CupEntity] {
        AppState.shared.settings.cups.filter { identifiers.contains($0.id) }.map(Self.entity)
    }

    @MainActor
    func suggestedEntities() async throws -> [CupEntity] {
        AppState.shared.settings.cups.map(Self.entity)
    }

    static func entity(_ cup: Cup) -> CupEntity { CupEntity(id: cup.id, name: cup.name, amountML: cup.amountML) }
}

struct LogDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Drink"
    static let description = IntentDescription("Logs a drink in Sip.")

    @Parameter(title: "Amount", default: 250, inclusiveRange: (1, 5000))
    var amount: Double

    @Parameter(title: "Unit", default: .milliliters)
    var unit: AmountUnit

    @Parameter(title: "Drink", default: .water)
    var drink: DrinkChoice

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$amount) \(\.$unit) of \(\.$drink)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        let ml = unit.milliliters(amount)
        state.logAmount(ml, drink: drink.kind, source: .intent)
        return .result(dialog: "Logged \(Volume.format(Volume.snap(ml, state.settings.unit), state.settings.unit)) of \(drink.kind.title.lowercased()). \(state.store.progress.percent)% of today's goal.")
    }
}

struct LogCupIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Cup"
    static let description = IntentDescription("Logs one of your quick-add cups.")

    @Parameter(title: "Cup")
    var cup: CupEntity

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        guard let found = state.settings.cups.first(where: { $0.id == cup.id }) else {
            return .result(dialog: "That cup isn't in Sip any more.")
        }
        state.log(cup: found, source: .intent)
        return .result(dialog: "Logged your \(found.name.lowercased()). \(state.store.progress.percent)% of today's goal.")
    }
}

struct LogWaterIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Water"
    static let description = IntentDescription("Logs your default cup.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        let cup = state.settings.defaultCup
        SipCommand.logDefault.perform(state, source: .intent)
        return .result(dialog: "Logged \(Volume.format(cup.amountML, state.settings.unit)). \(state.store.progress.percent)% of today's goal.")
    }
}

struct LogCoffeeIntent: AppIntent {
    static let title: LocalizedStringResource = "Log a Coffee"
    static let description = IntentDescription("Logs a cup of coffee (your coffee cup if you have one, otherwise 240 ml).")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        if let cup = state.settings.cups.first(where: { $0.drink == .coffee }) {
            state.log(cup: cup, source: .intent)
        } else {
            state.log(ml: 240, drink: .coffee, source: .intent)
        }
        var line = "Coffee logged."
        if let now = state.caffeineNow { line += " About \(Int(now.rounded())) mg of caffeine in you now." }
        return .result(dialog: "\(line)")
    }
}

struct UndoLastDrinkIntent: AppIntent {
    static let title: LocalizedStringResource = "Undo Last Drink"
    static let description = IntentDescription("Removes the last drink you logged today.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        guard let last = state.store.todayEntries.last else { return .result(dialog: "There's nothing to undo today.") }
        SipCommand.undo.perform(state, source: .intent)
        return .result(dialog: "Removed \(Volume.format(last.amountML, state.settings.unit)) of \(last.drink.title.lowercased()).")
    }
}

struct FinishedBottleIntent: AppIntent {
    static let title: LocalizedStringResource = "Finished My Bottle"
    static let description = IntentDescription("Logs one full bottle of your bottle size.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let state = AppState.shared
        SipCommand.refill.perform(state, source: .intent)
        return .result(dialog: "Bottle logged. That's \(state.refill.label).")
    }
}

struct HydrationStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Today's Hydration"
    static let description = IntentDescription("How much you've drunk today, your streak and level.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<Double> & ProvidesDialog {
        let state = AppState.shared
        let store = state.store
        let unit = state.settings.unit
        var line = "\(Volume.formatCompact(store.consumed, unit)) of \(Volume.formatCompact(store.goal, unit)), \(store.progress.percent)%."
        if store.streak.current > 0 { line += " \(store.streak.description)." }
        if state.settings.levelsEnabled { line += " Level \(state.derived.level.level), \(state.derived.level.title)." }
        return .result(value: store.consumed, dialog: "\(line)")
    }
}

struct PeekWidgetIntent: AppIntent {
    static let title: LocalizedStringResource = "Show the Sip Widget"
    static let description = IntentDescription("Brings the desktop widget above your windows for a moment.")

    @MainActor
    func perform() async throws -> some IntentResult {
        SipCommand.peek.perform(AppState.shared, source: .intent)
        return .result()
    }
}

struct OpenInsightsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Sip Insights"
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppState.shared.openInsights()
        return .result()
    }
}

/// Add to a Focus in System Settings → Focus → Focus Filters: while that
/// Focus is on, Sip holds reminders and the HUD (and can calm the water).
struct SipFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Set Sip's Focus Behaviour"
    static let description = IntentDescription("Pause Sip's reminders and HUD while this Focus is on.")

    // Optional on purpose: macOS calls `perform` with the defaults when the
    // Focus turns off, so "no value" has to mean "back to normal".
    @Parameter(title: "Pause reminders and the HUD")
    var quiet: Bool?

    @Parameter(title: "Calm the water")
    var calm: Bool?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: quiet == true ? "Reminders paused" : "Reminders on",
                              subtitle: calm == true ? "Calm water" : nil)
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        let settings = AppState.shared.settings
        settings.focusQuiet = quiet ?? false
        settings.focusCalmMotion = calm ?? false
        return .result()
    }
}

/// Phrases that work with no setup in Siri and Spotlight.
struct SipShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogWaterIntent(), phrases: ["Log water in \(.applicationName)", "Log a glass in \(.applicationName)",
                                                        "\(.applicationName) log water"],
                    shortTitle: "Log Water", systemImageName: "drop.fill")
        AppShortcut(intent: LogCoffeeIntent(), phrases: ["Log a coffee in \(.applicationName)"],
                    shortTitle: "Log Coffee", systemImageName: "cup.and.saucer.fill")
        AppShortcut(intent: LogCupIntent(), phrases: ["Log my \(\.$cup) in \(.applicationName)"],
                    shortTitle: "Log a Cup", systemImageName: "cup.and.heat.waves.fill")
        AppShortcut(intent: HydrationStatusIntent(), phrases: ["How much have I drunk in \(.applicationName)",
                                                               "\(.applicationName) progress"],
                    shortTitle: "Today's Progress", systemImageName: "chart.bar.fill")
        AppShortcut(intent: UndoLastDrinkIntent(), phrases: ["Undo my last drink in \(.applicationName)"],
                    shortTitle: "Undo Last Drink", systemImageName: "arrow.uturn.backward")
        AppShortcut(intent: FinishedBottleIntent(), phrases: ["I finished my bottle in \(.applicationName)"],
                    shortTitle: "Finished My Bottle", systemImageName: "arrow.triangle.2.circlepath")
    }
}
