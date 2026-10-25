import Foundation
import Observation
import SipCore

/// Hydration buddies through a shared folder (an iCloud Drive folder you
/// share with friends in Finder). Each Mac writes a small card with today's
/// numbers, never your history, and reads everyone else's. A nudge is a tiny
/// file addressed to one person. No server, no account.
@MainActor
@Observable
final class BuddiesService {
    private(set) var cards: [BuddyCard] = []
    @ObservationIgnored private unowned let state: AppState
    @ObservationIgnored private var watcher: FolderWatcher?
    @ObservationIgnored private var publish = Debouncer()
    @ObservationIgnored private var lastPublished: BuddyCard?

    init(state: AppState) { self.state = state }

    var folder: URL? {
        let path = state.settings.buddiesFolderPath
        guard state.settings.buddiesEnabled, !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    func start() {
        watcher?.stop()
        watcher = nil
        guard let folder, !DebugHooks.demo || DebugHooks.has("buddies") else { cards = []; return }
        let watcher = FolderWatcher { [weak self] in self?.read() }
        watcher.watch([folder])
        self.watcher = watcher
        read()
        writeCard()
    }

    /// Today's numbers changed: share them a little later (at most once a minute).
    func publishSoon() {
        guard folder != nil else { return }
        publish.schedule(after: 60) { [weak self] in self?.writeCard() }
    }

    func poke(_ card: BuddyCard) {
        guard let folder else { return }
        let poke = BuddyPoke(from: state.settings.buddyName, fromID: state.settings.buddyID, to: card.id,
                             message: "Time for some water 💧", sent: Date())
        _ = try? Buddies.send(poke, to: folder)
        state.showToast(Toast(icon: "hand.wave.fill", text: "Nudged \(card.name)", tint: state.settings.theme.surface), duration: 2)
    }

    private func writeCard() {
        guard let folder else { return }
        let store = state.store
        let card = BuddyCard(id: state.settings.buddyID, name: state.settings.buddyName, consumedML: store.consumed,
                             goalML: store.goal, percent: store.progress.percent, streak: store.streak.current,
                             level: state.derived.level.level, levelTitle: state.derived.level.title,
                             unit: state.settings.unit, updated: Date())
        var comparable = card
        comparable.updated = lastPublished?.updated ?? card.updated
        guard comparable != lastPublished else { return }
        if (try? Buddies.write(card, to: folder)) != nil { lastPublished = card }
    }

    private func read() {
        guard let folder else { return }
        let me = state.settings.buddyID
        cards = Buddies.fresh(Buddies.readCards(folder: folder).filter { $0.id != me }, now: Date())
        for (poke, url) in Buddies.readPokes(folder: folder, for: me) {
            try? FileManager.default.removeItem(at: url)
            guard Date().timeIntervalSince(poke.sent) < 6 * 3600 else { continue }
            state.reminders.notify(id: "sip.poke.\(poke.id)", title: "\(poke.from) nudged you", body: poke.message,
                                   route: "popover")
        }
    }
}
