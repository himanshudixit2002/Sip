import AppKit
import SwiftUI
import SipCore

/// The menu bar item: a small progress ring rather than a second bottle.
/// Click for today and every cup, right-click for the full menu.
@MainActor
final class StatusItemController: NSObject {
    private unowned let state: AppState
    private var item: NSStatusItem?

    init(state: AppState) {
        self.state = state
        super.init()
    }

    var isVisible: Bool { item?.isVisible ?? false }
    var button: NSStatusBarButton? { item?.button }

    func setVisible(_ visible: Bool) {
        if visible, item == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.target = self
                button.action = #selector(clicked)
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
                button.imagePosition = .imageLeading
            }
            self.item = item
            refresh()
        } else if !visible, let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func refresh() {
        guard let button = item?.button else { return }
        let progress = state.store.progress
        button.image = Self.ring(progress: progress)
        if state.settings.showPercentInMenuBar {
            button.title = " \(progress.percent)%"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        } else {
            button.title = ""
        }
        button.toolTip = "Sip — \(Volume.format(state.store.consumed, state.settings.unit)) of \(Volume.format(state.store.goal, state.settings.unit))"
    }

    @objc private func clicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            guard let item else { return }
            item.menu = MenuBuilder.make(state)
            item.button?.performClick(nil)
            item.menu = nil
        } else {
            state.togglePopover(anchor: .statusItem)
        }
    }

    /// A template ring filled clockwise to `progress`, with a drop in the
    /// middle that fills in once the goal is reached.
    static func ring(progress: Double) -> NSImage {
        let image = NSImage(size: NSSize(width: 16, height: 16), flipped: false) { rect in
            let center = NSPoint(x: rect.midX, y: rect.midY)
            let radius: CGFloat = 6.4
            let track = NSBezierPath()
            track.appendArc(withCenter: center, radius: radius, startAngle: 0, endAngle: 360)
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.3).setStroke()
            track.stroke()

            let f = CGFloat(min(max(progress, 0), 1))
            if f > 0.005 {
                let arc = NSBezierPath()
                arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * f, clockwise: true)
                arc.lineWidth = 2.2
                arc.lineCapStyle = .round
                NSColor.black.setStroke()
                arc.stroke()
            }

            // A small drop: outline until the goal is met, then solid.
            let drop = NSBezierPath()
            drop.move(to: NSPoint(x: center.x, y: center.y + 3.6))
            drop.curve(to: NSPoint(x: center.x, y: center.y - 3.0),
                       controlPoint1: NSPoint(x: center.x + 3.9, y: center.y - 0.6),
                       controlPoint2: NSPoint(x: center.x + 2.6, y: center.y - 3.0))
            drop.curve(to: NSPoint(x: center.x, y: center.y + 3.6),
                       controlPoint1: NSPoint(x: center.x - 2.6, y: center.y - 3.0),
                       controlPoint2: NSPoint(x: center.x - 3.9, y: center.y - 0.6))
            drop.close()
            NSColor.black.setFill()
            NSColor.black.setStroke()
            if progress >= 1 {
                drop.fill()
            } else {
                drop.lineWidth = 1
                drop.stroke()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Sip, \(progress.percent) percent"
        return image
    }
}

/// Where the popover points from.
enum PopoverAnchor {
    /// The widget if it's showing, otherwise the menu bar.
    case automatic
    case widget
    case statusItem
}

/// The popover: today's numbers, every cup, a custom amount and today's list.
/// It's a floating card placed by hand, under the menu bar icon or beside the
/// widget. NSPopover isn't used: it sized itself before its SwiftUI content
/// had laid out and then grew upward, off the top of the screen under the
/// menu bar, and it lands well above a point on the desktop-level widget. The
/// card is measured first and kept inside the screen. Its views exist only
/// while it's open.
@MainActor
final class PopoverController: NSObject, NSWindowDelegate {
    private unowned let state: AppState
    private var card: KeyPanel?
    private var outsideClicks: Any?
    let presence = PopoverPresence()
    /// Called after it closes, so whatever it was anchored to can settle back.
    var onClose: (() -> Void)?
    private var closedAt: CFTimeInterval = 0

    init(state: AppState) {
        self.state = state
        super.init()
    }

    var isShown: Bool { card != nil }

    /// Below (or above) a rectangle on screen: the menu bar icon or the
    /// widget's card.
    func show(below target: NSRect, above: Bool, screen: NSScreen?) {
        // The click that closed it shouldn't open it straight back up.
        guard !isShown, CACurrentMediaTime() - closedAt > 0.3 else { return }
        let host = NSHostingView(rootView: PopoverView(state: state, presence: presence)
            .background(VisualEffectBlur(material: .popover))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.12))))
        let size = host.fittingSize
        let panel = KeyPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.configureTransparent(level: .popUpMenu, shadow: true)
        panel.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]
        panel.contentView = host
        panel.delegate = self

        let visible = (screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var origin = NSPoint(x: target.midX - size.width / 2,
                             y: above ? target.maxY + 8 : target.minY - 8 - size.height)
        origin.x = min(max(origin.x, visible.minX + 8), visible.maxX - size.width - 8)
        origin.y = min(max(origin.y, visible.minY + 8), visible.maxY - size.height - 8)
        panel.setFrameOrigin(origin)
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            panel.animator().alphaValue = 1
        }
        card = panel
        presence.shown = true
        // Clicking anywhere else closes it, like a popover.
        outsideClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated { self?.close() }
        }
    }

    func close() {
        if let card {
            self.card = nil
            card.orderOut(nil)
            card.contentView = nil
            if let outsideClicks { NSEvent.removeMonitor(outsideClicks) }
            outsideClicks = nil
            didClose()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        // Another window took the keyboard (Settings, Insights, another app):
        // close like a popover would. Checked a moment later, because a
        // picker's menu briefly takes over too.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            guard let self, let card = self.card, !card.isKeyWindow, NSApp.modalWindow == nil else { return }
            if NSApp.keyWindow != nil || !NSApp.isActive { self.close() }
        }
    }

    private func didClose() {
        presence.shown = false
        presence.focusCustom = false
        closedAt = CACurrentMediaTime()
        onClose?()
        // Its view tree is gone; hand the freed pages back once it's torn down.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { Memory.relieve() }
    }
}

@Observable
final class PopoverPresence {
    var shown = false
    /// Opened from "Custom Amount…": put the cursor in the amount.
    var focusCustom = false
}
