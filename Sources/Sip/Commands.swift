import AppKit
import SipCore

/// Where an action came from. Logging from somewhere you can't see the
/// widget (a hotkey, Siri, the command line, your phone) shows the HUD so
/// you still get feedback.
enum LogSource: String {
    case widget, popover, menu, hotkey, quickLog, url, cli, inbox, intent, notification, settings, debug

    /// True when the drink was logged without looking at Sip.
    var isRemote: Bool {
        switch self {
        case .hotkey, .quickLog, .url, .cli, .inbox, .intent, .notification: return true
        case .widget, .popover, .menu, .settings, .debug: return false
        }
    }
}

/// Every action Sip offers, in one place. The right-click menu, the popover,
/// links, hotkeys, notification buttons, App Intents and the `sip` command
/// all run these, so each behaves the same wherever it's started from.
@MainActor
enum SipCommand: String, CaseIterable {
    case logDefault, refill, quickLog, customAmount, undo, peek, toggleWidget, insights, share, settings, quit

    func title(_ state: AppState) -> String {
        let unit = state.settings.unit
        switch self {
        case .logDefault:
            let cup = state.settings.defaultCup
            return "Log \(cup.name) — \(Volume.format(cup.amountML, unit))"
        case .refill: return "Finished My Bottle — \(Volume.format(state.settings.bottleSizeML, unit))"
        case .quickLog: return "Quick Log…"
        case .customAmount: return "Custom Amount…"
        case .undo:
            guard let last = state.store.todayEntries.last else { return "Undo" }
            return "Undo \(Volume.format(last.amountML, unit)) \(last.drink.title.lowercased())"
        case .peek: return "Bring Widget Forward"
        case .toggleWidget: return state.settings.widgetVisible ? "Hide Widget" : "Show Widget"
        case .insights: return "Insights…"
        case .share: return "Share My Week…"
        case .settings: return "Settings…"
        case .quit: return "Quit Sip"
        }
    }

    var symbol: String {
        switch self {
        case .logDefault: return "drop.fill"
        case .refill: return "arrow.triangle.2.circlepath"
        case .quickLog: return "text.cursor"
        case .customAmount: return "slider.horizontal.3"
        case .undo: return "arrow.uturn.backward"
        case .peek: return "macwindow.on.rectangle"
        case .toggleWidget: return "rectangle.on.rectangle"
        case .insights: return "chart.bar.xaxis"
        case .share: return "square.and.arrow.up"
        case .settings: return "gearshape"
        case .quit: return "power"
        }
    }

    /// Shown in menus. Hotkeys are global and listed with their own setting.
    var keyEquivalent: String {
        switch self {
        case .undo: return "z"
        case .settings: return ","
        case .quit: return "q"
        default: return ""
        }
    }

    func isEnabled(_ state: AppState) -> Bool {
        switch self {
        case .undo: return !state.store.todayEntries.isEmpty
        case .peek: return state.settings.widgetVisible
        default: return true
        }
    }

    func perform(_ state: AppState, source: LogSource) {
        switch self {
        case .logDefault: state.log(cup: state.settings.defaultCup, source: source)
        case .refill: state.logRefill(source: source)
        case .quickLog: state.toggleQuickLog()
        case .customAmount: state.showPopover(focusCustom: true)
        case .undo: state.undo(source: source)
        case .peek: state.peek()
        case .toggleWidget: state.settings.widgetVisible.toggle()
        case .insights: state.openInsights()
        case .share: ShareCardView.save(state: state)
        case .settings: state.openSettings()
        case .quit: NSApp.terminate(nil)
        }
    }
}

/// The right-click menu, for both the widget and the menu bar icon.
@MainActor
enum MenuBuilder {
    static func make(_ state: AppState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let settings = state.settings

        for cup in settings.cups {
            let item = ClosureMenuItem("Log \(cup.name) — \(Volume.format(cup.amountML, settings.unit))") { [weak state] in
                state?.log(cup: cup, source: .menu)
            }
            item.image = NSImage(systemSymbolName: cup.symbol, accessibilityDescription: nil)
            menu.addItem(item)
        }
        add(.refill, to: menu, state)
        add(.quickLog, to: menu, state)
        add(.customAmount, to: menu, state)
        if SipCommand.undo.isEnabled(state) { add(.undo, to: menu, state) }
        menu.addItem(.separator())

        menu.addItem(choiceSubmenu("Size", WidgetSize.allCases, current: settings.widgetSize, title: \.title) { [weak state] in
            state?.settings.widgetSize = $0
        })
        if settings.widgetVisible { add(.peek, to: menu, state) }
        add(.toggleWidget, to: menu, state)
        menu.addItem(.separator())
        add(.insights, to: menu, state)
        add(.share, to: menu, state)
        add(.settings, to: menu, state)
        menu.addItem(.separator())
        add(.quit, to: menu, state)
        return menu
    }

    private static func add(_ command: SipCommand, to menu: NSMenu, _ state: AppState) {
        let item = ClosureMenuItem(command.title(state), key: command.keyEquivalent,
                                   enabled: command.isEnabled(state)) { [weak state] in
            guard let state else { return }
            command.perform(state, source: .menu)
        }
        item.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
        menu.addItem(item)
    }

    /// A submenu of options with a tick on the current one.
    static func choiceSubmenu<T: Equatable>(_ title: String, _ options: [T], current: T, title label: KeyPath<T, String>,
                                            set: @escaping (T) -> Void) -> NSMenuItem {
        let submenu = NSMenu()
        for option in options {
            submenu.addItem(ClosureMenuItem(option[keyPath: label], state: option == current ? .on : .off) { set(option) })
        }
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = submenu
        return item
    }
}
