import AppKit
import Darwin
import QuartzCore
import SwiftUI

/// A borderless, transparent panel that never activates the app. It sits
/// either just above the desktop icons, behind every window like a system
/// widget, or above other windows.
final class WidgetPanel: NSPanel {
    var contextMenuProvider: (() -> NSMenu?)?
    var onMouseDown: (() -> Void)?

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 220),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        animationBehavior = .none
        isMovableByWindowBackground = false
        title = "Sip"
    }

    /// Never takes keyboard focus: clicking the widget must not pull typing
    /// away from the app you're working in. Nothing on the card needs keys.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Right-click is handled here rather than in SwiftUI so it works no
    /// matter which view is under the pointer.
    override func sendEvent(_ event: NSEvent) {
        switch event.type {
        case .rightMouseDown:
            if let menu = contextMenuProvider?(), let view = contentView {
                NSMenu.popUpContextMenu(menu, with: event, for: view)
                return
            }
        case .leftMouseDown:
            onMouseDown?()
        default:
            break
        }
        super.sendEvent(event)
    }
}

/// Lets the first click on an inactive window reach the button under it.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class WidgetController: NSObject {
    /// Room around the card for its shadow.
    static let margin: CGFloat = 24

    let panel = WidgetPanel()
    let visibility = WidgetVisibility()
    private unowned let state: AppState
    private var hosting: FirstClickHostingView<WidgetRoot>!
    private var observers: [NSObjectProtocol] = []
    private var screensAsleep = false
    /// Other apps' windows hide the card. Read by the logging HUD.
    private(set) var covered = false
    private var coverageTimer: Timer?
    private var relief = Debouncer()
    /// Raised above other windows for a moment (Peek).
    private(set) var peeking = false
    private var peekEnd = Debouncer()
    private var peekMonitor: Any?

    // Window-motion tracking for the slosh.
    private var motionTimer: Timer?
    private var lastSample: (time: CFTimeInterval, origin: CGPoint, vx: Double, vy: Double)?
    private var stillSince: CFTimeInterval?
    private var startOrigin: CGPoint?

    init(state: AppState) {
        self.state = state
        super.init()
        hosting = FirstClickHostingView(rootView: WidgetRoot(state: state, visibility: visibility))
        hosting.sizingOptions = []
        panel.contentView = hosting
        panel.contextMenuProvider = { [weak self] in self.map { MenuBuilder.make($0.state) } }
        panel.onMouseDown = { [weak self] in self?.beginMotionTracking() }

        let tracking = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                      owner: self, userInfo: nil)
        hosting.addTrackingArea(tracking)

        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: panel,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateHidden() }
        })
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                                            queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.keepOnScreen() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = true; self?.updateHidden() }
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensAsleep = false; self?.updateHidden() }
        })
        // Switching apps is the most common way the widget gets covered or
        // uncovered; check straight away rather than waiting for the timer.
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCoverage() }
        })

        applySettings(resize: true)
        restorePosition()
        startCoverageWatch()
    }

    // MARK: Showing

    func show() {
        panel.orderFrontRegardless()
        updateHidden()
    }

    func hide() {
        endPeek()
        panel.orderOut(nil)
        updateHidden()
    }

    /// Whether the card can actually be seen right now.
    var isOnScreen: Bool { panel.isVisible && !covered && !screensAsleep }

    // MARK: Peek

    /// Lifts the widget above every window for a moment, then lets it sink
    /// back. With no duration it stays up until `endPeek()` or a click
    /// somewhere else.
    func peek(seconds: Double? = 8) {
        guard panel.isVisible else { return }
        if !peeking {
            peeking = true
            panel.level = .floating
            panel.alphaValue = 0.4
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 1
            }
            if covered { covered = false; updateHidden() }
            // A click in another app ends it. Global mouse monitors need no
            // permission.
            peekMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated { self?.endPeek() }
            }
        }
        if let seconds {
            peekEnd.schedule(after: seconds) { [weak self] in self?.endPeek() }
        } else {
            peekEnd.cancel()
        }
    }

    func endPeek() {
        guard peeking else { return }
        peeking = false
        peekEnd.cancel()
        if let peekMonitor { NSEvent.removeMonitor(peekMonitor) }
        peekMonitor = nil
        applySettings(resize: false)
        checkCoverage()
    }

    func setVisible(_ visible: Bool) { visible ? show() : hide() }

    private func updateHidden() {
        let hidden = !panel.isVisible || screensAsleep || covered || !panel.occlusionState.contains(.visible)
        guard visibility.hidden != hidden else { return }
        visibility.hidden = hidden
        if hidden { scheduleMemoryRelief() }
    }

    // MARK: Coverage

    /// macOS only reports a window as occluded when opaque windows cover it,
    /// and many apps draw translucent windows. So once a second the windows
    /// stacked above the widget are checked directly; when they cover the
    /// card, nothing is drawn. Window bounds don't need Screen Recording
    /// permission.
    private func startCoverageWatch() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkCoverage() }
        }
        timer.tolerance = 0.4
        RunLoop.main.add(timer, forMode: .common)
        coverageTimer = timer
    }

    private func checkCoverage() {
        // `cover` pretends the widget is buried, for benchmarking that state.
        let nowCovered = panel.isVisible && (DebugHooks.has("cover") || coveredFraction() >= 0.95)
        if nowCovered != covered {
            covered = nowCovered
            updateHidden()
        }
    }

    /// Share of the card hidden by other apps' windows, sampled on a grid.
    func coveredFraction() -> Double {
        guard panel.windowNumber > 0, let screenHeight = NSScreen.screens.first?.frame.height else { return 0 }
        let me = ProcessInfo.processInfo.processIdentifier
        // Normal windows, floating panels and the Dock; not the menu bar,
        // overlays or invisible helper windows.
        let blockers = WindowList.onScreen(above: CGWindowID(panel.windowNumber))
            .filter { $0.ownerPID != me && (0..<24).contains($0.layer) && $0.alpha > 0.3
                && $0.bounds.width > 40 && $0.bounds.height > 40 }
            .map(\.bounds)
        guard !blockers.isEmpty else { return 0 }
        // The card, in the window list's top-left coordinates.
        let card = panel.frame.insetBy(dx: Self.margin, dy: Self.margin)
        let top = screenHeight - card.maxY
        let columns = 8, rows = 6
        var hidden = 0
        for row in 0..<rows {
            for column in 0..<columns {
                let p = CGPoint(x: card.minX + card.width * (CGFloat(column) + 0.5) / CGFloat(columns),
                                y: top + card.height * (CGFloat(row) + 0.5) / CGFloat(rows))
                if blockers.contains(where: { $0.contains(p) }) { hidden += 1 }
            }
        }
        return Double(hidden) / Double(rows * columns)
    }

    /// Animation leaves freed heap pages behind. Once the widget goes quiet,
    /// hand them back to the system.
    private func scheduleMemoryRelief() {
        relief.schedule(after: 2) { Memory.relieve() }
    }

    // MARK: Hover

    // The tracking area's owner is a plain NSObject, so the Objective-C names
    // have to be spelled out: Swift would export `mouseEnteredWith:` and
    // AppKit, sending `mouseEntered:`, threw an exception on every hover.
    @objc(mouseEntered:) func mouseEntered(with event: NSEvent) { visibility.hovering = true }
    @objc(mouseExited:) func mouseExited(with event: NSEvent) { visibility.hovering = false }

    /// The card's ⋯ button: the same menu as a right-click, opened from its
    /// top corner.
    func showMenu() {
        guard let view = panel.contentView else { return }
        let card = cardScreenRect
        let inWindow = panel.convertPoint(fromScreen: NSPoint(x: card.maxX - 14, y: card.maxY - 10))
        let point = view.convert(inWindow, from: nil)
        let menu = MenuBuilder.make(state)
        // Let the button finish its click before the menu takes over the
        // event loop.
        DispatchQueue.main.async { menu.popUp(positioning: nil, at: point, in: view) }
    }

    // MARK: Settings

    /// The card itself on screen, without the shadow margin.
    var cardScreenRect: NSRect {
        let scale = state.settings.widgetScale
        let size = state.settings.widgetSize.cardSize
        let frame = panel.frame
        return NSRect(x: frame.midX - size.width * scale / 2, y: frame.midY - size.height * scale / 2,
                      width: size.width * scale, height: size.height * scale)
    }

    var desktopLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    func applySettings(resize: Bool) {
        let settings = state.settings
        panel.level = peeking || settings.placement == .floating ? .floating : desktopLevel
        var behavior: NSWindow.CollectionBehavior = [.stationary, .ignoresCycle]
        if settings.allSpaces { behavior.insert(.canJoinAllSpaces) }
        // Only a floating widget may follow you into full-screen apps; on the
        // desktop it stays out of them entirely.
        if settings.placement == .floating { behavior.insert(.fullScreenAuxiliary) }
        panel.collectionBehavior = behavior
        panel.isMovable = !settings.lockPosition
        if resize { applySize() }
    }

    /// The window is the card plus a shadow margin. Resizing keeps the card's
    /// top-left corner where it was.
    func applySize() {
        let settings = state.settings
        let card = settings.widgetSize.cardSize
        let size = NSSize(width: card.width * settings.widgetScale + Self.margin * 2,
                          height: card.height * settings.widgetScale + Self.margin * 2)
        var frame = panel.frame
        let top = frame.maxY
        frame.size = size
        frame.origin.y = top - size.height
        panel.setFrame(frame, display: true)
        keepOnScreen()
    }

    // MARK: Position

    private var defaults: UserDefaults { DebugHooks.defaults }

    func resetPosition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let vf = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(x: vf.maxX - size.width - 20 + Self.margin, y: vf.maxY - size.height - 20 + Self.margin)
        panel.setFrame(NSRect(origin: origin, size: size), display: true, animate: panel.isVisible)
        savePosition()
    }

    private func restorePosition() {
        if let saved = defaults.array(forKey: "widgetOrigin") as? [Double], saved.count == 2 {
            let frame = NSRect(origin: NSPoint(x: saved[0], y: saved[1]), size: panel.frame.size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame.insetBy(dx: 40, dy: 40)) }) {
                panel.setFrameOrigin(frame.origin)
                // The size may have changed since the position was saved.
                keepOnScreen()
                return
            }
        }
        resetPosition()
    }

    private func savePosition() {
        defaults.set([Double(panel.frame.minX), Double(panel.frame.minY)], forKey: "widgetOrigin")
    }

    /// Pulls the card back if a display went away or the size grew past an edge.
    private func keepOnScreen() {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame.insetBy(dx: -Self.margin, dy: -Self.margin)
        var frame = panel.frame
        frame.origin.x = min(max(frame.minX, vf.minX), vf.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, vf.minY), vf.maxY - frame.height)
        if frame.origin != panel.frame.origin { panel.setFrameOrigin(frame.origin) }
    }

    /// After a drag, an edge within reach pulls the card to a tidy gap.
    private func snapToEdges() {
        guard state.settings.snapToEdges, let screen = panel.screen else { return }
        let vf = screen.visibleFrame
        let card = panel.frame.insetBy(dx: Self.margin, dy: Self.margin)
        let reach: CGFloat = 28, gap: CGFloat = 16
        var dx: CGFloat = 0, dy: CGFloat = 0
        if abs(card.minX - vf.minX) < reach { dx = vf.minX + gap - card.minX }
        if abs(vf.maxX - card.maxX) < reach { dx = vf.maxX - gap - card.maxX }
        if abs(card.minY - vf.minY) < reach { dy = vf.minY + gap - card.minY }
        if abs(vf.maxY - card.maxY) < reach { dy = vf.maxY - gap - card.maxY }
        guard dx != 0 || dy != 0 else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrameOrigin(NSPoint(x: panel.frame.minX + dx, y: panel.frame.minY + dy))
        }
    }

    // MARK: Motion → slosh

    /// Samples the window's position at display rate while the mouse is down,
    /// and turns changes in velocity into sloshing. Sampling is used rather
    /// than move notifications because a system-driven window drag doesn't
    /// reliably report every step.
    private func beginMotionTracking() {
        guard motionTimer == nil else { return }
        lastSample = nil
        stillSince = nil
        startOrigin = panel.frame.origin
        let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleMotion() }
        }
        RunLoop.main.add(timer, forMode: .common)
        motionTimer = timer
    }

    private func sampleMotion() {
        let now = CACurrentMediaTime()
        let origin = panel.frame.origin
        let buttonDown = NSEvent.pressedMouseButtons & 1 != 0
        if let last = lastSample {
            let dt = max(now - last.time, 1.0 / 240)
            let vx = Double(origin.x - last.origin.x) / dt
            let vy = Double(origin.y - last.origin.y) / dt
            // Light smoothing: a single dropped frame shouldn't read as a jolt.
            let svx = last.vx * 0.35 + vx * 0.65
            let svy = last.vy * 0.35 + vy * 0.65
            let dvx = svx - last.vx, dvy = svy - last.vy
            if abs(dvx) + abs(dvy) > 4 {
                SipEvents.post(SipEvents.windowMoved, object: panel, ["dvx": dvx, "dvy": -dvy])
            }
            lastSample = (now, origin, svx, svy)
            if abs(svx) + abs(svy) < 2 {
                stillSince = stillSince ?? now
            } else {
                stillSince = nil
            }
        } else {
            lastSample = (now, origin, 0, 0)
        }
        if !buttonDown, let still = stillSince, now - still > 0.08 {
            endMotionTracking()
        }
    }

    private func endMotionTracking() {
        motionTimer?.invalidate()
        motionTimer = nil
        let moved = startOrigin.map { hypot($0.x - panel.frame.minX, $0.y - panel.frame.minY) > 1 } ?? false
        lastSample = nil
        guard moved else { return }
        snapToEdges()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.savePosition() }
    }

    // MARK: Diagnostics

    func diagnostics() -> String {
        let f = panel.frame
        return """
        widget: visible=\(panel.isVisible) level=\(panel.level.rawValue) (desktop+1=\(desktopLevel.rawValue)) \
        frame=\(Int(f.minX)),\(Int(f.minY)) \(Int(f.width))x\(Int(f.height)) \
        occluded=\(!panel.occlusionState.contains(.visible)) covered=\(String(format: "%.2f", coveredFraction())) \
        hidden=\(visibility.hidden) peeking=\(peeking) \
        spaces=\(panel.collectionBehavior.contains(.canJoinAllSpaces) ? "all" : "one") movable=\(panel.isMovable)
        """
    }
}
