import AppKit

/// Bootstrapped as a plain AppKit application rather than a SwiftUI `App`:
/// Sip is a desktop widget with a menu bar icon, and no main window. It has
/// no Dock icon except while one of its windows is open.
@main
enum SipMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Another copy of Sip is already running and this one is handing over.
    private var yielding = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            if SingleInstance.yield() { yielding = true; return }
            AppState.shared.start()
            AppMenu.install(AppState.shared)
        }
    }

    /// `sip://` links. See `URLAction` for the list.
    func application(_ application: NSApplication, open urls: [URL]) {
        MainActor.assumeIsolated {
            guard !yielding else { return }
            for url in urls { AppState.shared.handle(url) }
        }
    }

    /// Opened again from Spotlight, Launchpad, Finder or the Dock while
    /// already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainActor.assumeIsolated {
            guard !yielding else { return }
            AppState.shared.reopened()
        }
        return false
    }

    /// Closing Settings or Insights must not quit the widget.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
