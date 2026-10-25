import AppKit

/// Sip's menu bar menus. They show while one of its windows (Settings,
/// Insights, Welcome) is open, when Sip behaves like a normal app, and they
/// carry the standard keys: ⌘, ⌘W ⌘Q, and copy and paste in text fields.
@MainActor
enum AppMenu {
    static func install(_ state: AppState) {
        let main = NSMenu()
        main.addItem(submenu("Sip", appMenu(state)))
        main.addItem(submenu("Edit", editMenu()))
        let window = windowMenu()
        main.addItem(submenu("Window", window))
        NSApp.mainMenu = main
        NSApp.windowsMenu = window
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        menu.title = title
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu(_ state: AppState) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = AppMenuDelegate.shared
        AppMenuDelegate.shared.state = state
        AppMenuDelegate.shared.fill(menu)
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Undo", action: Selector(("undo:")), keyEquivalent: "z"))
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        menu.addItem(NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        menu.addItem(NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        menu.addItem(NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        return menu
    }
}

/// Rebuilds the Sip menu each time it opens, so "Show/Hide Widget" and the
/// Undo line read correctly.
@MainActor
private final class AppMenuDelegate: NSObject, NSMenuDelegate {
    static let shared = AppMenuDelegate()
    weak var state: AppState?

    func menuNeedsUpdate(_ menu: NSMenu) { fill(menu) }

    func fill(_ menu: NSMenu) {
        menu.removeAllItems()
        guard let state else { return }
        menu.addItem(ClosureMenuItem("About Sip") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        menu.addItem(.separator())
        add(.settings, to: menu, state)
        add(.insights, to: menu, state)
        menu.addItem(.separator())
        add(.logDefault, to: menu, state)
        add(.quickLog, to: menu, state)
        add(.toggleWidget, to: menu, state)
        menu.addItem(.separator())
        let hide = NSMenuItem(title: "Hide Sip", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        menu.addItem(hide)
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(others)
        menu.addItem(.separator())
        add(.quit, to: menu, state)
    }

    private func add(_ command: SipCommand, to menu: NSMenu, _ state: AppState) {
        let item = ClosureMenuItem(command.title(state), key: command.keyEquivalent,
                                   enabled: command.isEnabled(state)) { [weak state] in
            guard let state else { return }
            command.perform(state, source: .menu)
        }
        menu.addItem(item)
    }
}

/// Only one Sip runs at a time. Two would each put a bottle on the desktop
/// and both write the same history, which is how drinks once ended up logged
/// in a stray build. The copy in Applications wins: it asks any other copy to
/// quit, and any other copy shows the running one and quits itself.
@MainActor
enum SingleInstance {
    static let installedURL = URL(fileURLWithPath: "/Applications/Sip.app")

    /// True when this copy is stepping aside and must not start.
    static func yield() -> Bool {
        // Tests run a scratch copy next to the real one on purpose.
        guard DebugHooks.dataDirectory == nil, let id = Bundle.main.bundleIdentifier else { return false }
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != me }
        guard !others.isEmpty else { return false }
        if Bundle.main.bundleURL.resolvingSymlinksInPath() == installedURL.resolvingSymlinksInPath() {
            others.forEach { $0.terminate() }
            return false
        }
        let running = others.first(where: { $0.bundleURL?.resolvingSymlinksInPath() == installedURL.resolvingSymlinksInPath() })
            ?? others[0]
        if let url = running.bundleURL {
            // Opening a running app again shows its Settings.
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        }
        NSApp.terminate(nil)
        return true
    }
}
