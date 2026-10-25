import Foundation
import SipCore
import WidgetKit

/// Keeps the system widget and Control Center in step: writes a small,
/// already-formatted summary and asks WidgetKit to reload. A burst of changes
/// writes once, and nothing is written when nothing the widget shows changed.
@MainActor
final class WidgetBridge {
    private var debounce = Debouncer()
    private var lastWritten: WidgetSnapshot?

    func update(from state: AppState) {
        guard !DebugHooks.demo || DebugHooks.has("widgetbridge") else { return }
        debounce.schedule(after: 1) { [weak self, weak state] in
            guard let self, let state else { return }
            self.write(Self.snapshot(state))
        }
    }

    private func write(_ snapshot: WidgetSnapshot) {
        var comparable = snapshot
        comparable.updated = lastWritten?.updated ?? snapshot.updated
        guard comparable != lastWritten else { return }
        do {
            try snapshot.write()
            lastWritten = snapshot
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            // The widget keeps its last summary; nothing else depends on this.
        }
    }

    private static func snapshot(_ state: AppState) -> WidgetSnapshot {
        let store = state.store
        let settings = state.settings
        let unit = settings.unit
        let theme = settings.theme
        let days = store.recentDays(7)
        return WidgetSnapshot(
            progress: store.progress,
            consumedText: Volume.formatCompact(store.consumed, unit),
            goalText: Volume.formatCompact(store.goal, unit),
            streak: store.streak.current,
            level: state.derived.level.level,
            levelTitle: state.derived.level.title,
            challenge: state.derived.challenge?.challenge.title,
            challengeDone: state.derived.challenge?.done ?? false,
            cups: settings.cups.prefix(3).map {
                WidgetSnapshot.Cup(name: $0.name, label: "+\(Volume.displayNumber($0.amountML, unit).formatted())", symbol: $0.symbol)
            },
            week: days.map {
                WidgetSnapshot.Day(letter: $0.key.weekdaySymbol(short: true), progress: $0.progress, met: $0.met,
                                   isToday: $0.key == store.today)
            },
            colors: [theme.surface, theme.mid, theme.deep].map(\.hexValue),
            updated: Date())
    }
}
