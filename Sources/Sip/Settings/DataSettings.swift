import AppKit
import SwiftUI
import SipCore
import UniformTypeIdentifiers

// MARK: - Data

final class DayEditorModel: ObservableObject {
    @Published var day = Date()
    @Published var confirmingReset = false
    @Published var message: String?
}

struct DataSettings: View {
    let state: AppState
    let store: HydrationStore
    @StateObject private var model = DayEditorModel()

    var body: some View {
        let settings = state.settings
        let unit = settings.unit
        let picked = Calendar.current.dateComponents([.year, .month, .day], from: model.day)
        let key = DayKey(year: picked.year!, month: picked.month!, day: picked.day!)
        Form {
            if let error = store.loadError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
            }
            Section("History") {
                LabeledContent("Drinks logged", value: "\(store.history.entries.count)")
                LabeledContent("Days tracked", value: "\(store.summaries.count)")
                FileRow(title: "Stored at", url: store.fileURL)
                HStack {
                    Button("Export CSV…") { export() }
                    Button("Import CSV…") { importCSV() }
                    Spacer()
                    if let message = model.message {
                        Text(message).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Section {
                DatePicker("Day", selection: $model.day, in: ...Date(), displayedComponents: .date)
                let entries = store.entries(on: key)
                if entries.isEmpty {
                    Text("No drinks on this day.").foregroundStyle(.secondary)
                } else {
                    ForEach(entries) { entry in
                        EntryRow(entry: entry, unit: unit, theme: settings.theme) { state.delete(entry, source: .settings) }
                    }
                    let summary = store.summary(for: key)
                    Text("\(Volume.format(summary.effectiveML, unit)) of \(Volume.format(summary.goalML, unit)) · \(summary.met ? "goal met" : "goal missed")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                CustomAmountView(state: state, pickTime: store.clock.time(12 * 60, on: key)) { ml, drink, time in
                    addPast(key: key, ml: ml, drink: drink, time: time ?? Date())
                }
            } header: {
                Text("Edit a day")
            } footer: {
                FooterText("For drinks you forgot to log. Streaks update straight away.")
            }

            BackupsSection(state: state)

            Section {
                Button("Erase All History…", role: .destructive) { model.confirmingReset = true }
            }
        }
        .confirmationDialog("Erase all of Sip's history?", isPresented: $model.confirmingReset) {
            Button("Erase Everything", role: .destructive) {
                store.resetAll()
                state.historyReplaced()
            }
        } message: {
            Text("Every drink and streak is deleted. Export a CSV first if you might want it back.")
        }
    }

    private func addPast(key: DayKey, ml: Double, drink: DrinkKind, time: Date) {
        let c = Calendar.current.dateComponents([.hour, .minute], from: time)
        let minutes = (c.hour ?? 12) * 60 + (c.minute ?? 0)
        var date = store.clock.time(minutes, on: key)
        // Times before the day boundary belong to the next calendar date.
        if date < store.clock.start(of: key) { date = store.clock.time(minutes, on: key.next) }
        guard date <= Date() else { model.message = "That time hasn't happened yet."; return }
        state.logAmount(ml, drink: drink, source: .settings, at: date)
        model.message = "Added."
    }

    private func export() {
        Modal.save(name: "Sip history.csv", types: [.commaSeparatedText]) { url in
            try store.exportCSV().write(to: url, atomically: true, encoding: .utf8)
            model.message = "Exported \(store.history.entries.count) drinks."
        }
    }

    private func importCSV() {
        guard let url = Modal.open(types: [.commaSeparatedText, .plainText]),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let parsed = HistoryCSV.parse(text)
        store.importEntries(parsed.entries)
        state.historyReplaced()
        model.message = "Imported \(parsed.entries.count) drinks" + (parsed.skipped > 0 ? ", skipped \(parsed.skipped) rows." : ".")
    }
}


final class BackupsModel: ObservableObject {
    @Published var backups: [BackupInfo] = []
    @Published var restoring: BackupInfo?
    @Published var message: String?
}

/// Daily copies of your history, and putting one back.
private struct BackupsSection: View {
    let state: AppState
    @StateObject private var model = BackupsModel()

    var body: some View {
        Section {
            Toggle("Back up every day", isOn: Binding(get: { state.settings.backupsEnabled },
                                                      set: { state.settings.backupsEnabled = $0 }))
            ForEach(model.backups.prefix(11), id: \.url) { backup in
                HStack {
                    Text(backup.day.date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year()))
                    Spacer()
                    Text(backup.entryCount.map { "\($0) drinks" } ?? ByteCountFormatter.string(fromByteCount: Int64(backup.size), countStyle: .file))
                        .foregroundStyle(.secondary)
                    Button("Restore…") { model.restoring = backup }
                }
            }
            HStack {
                Button("Back Up Now") { backUpNow() }
                Button("Show Backups") { NSWorkspace.shared.open(SipPaths.backupsFolder) }
                Spacer()
                if let message = model.message { Text(message).font(.caption).foregroundStyle(.secondary) }
            }
        } header: {
            Text("Backups")
        } footer: {
            FooterText("Sip keeps the last 7 days and one a week for a month before that, in ~/Library/Application Support/Sip/Backups. Restoring replaces today's history with the backup.")
        }
        .onAppear { reload() }
        .confirmationDialog("Restore this backup?", isPresented: Binding(get: { model.restoring != nil }, set: { if !$0 { model.restoring = nil } })) {
            Button("Restore", role: .destructive) {
                guard let backup = model.restoring else { return }
                do {
                    try state.store.restore(from: backup.url)
                    state.historyReplaced()
                    model.message = "Restored."
                } catch {
                    model.message = error.localizedDescription
                }
            }
        } message: {
            Text("Drinks logged since then will be replaced by what's in the backup. A copy of today's history is saved first.")
        }
    }

    private func reload() {
        model.backups = Backups.list(folder: SipPaths.backupsFolder).sorted { $0.day > $1.day }
    }

    private func backUpNow() {
        do {
            let made = try Backups.run(historyURL: state.store.fileURL, folder: SipPaths.backupsFolder, today: state.store.today)
            model.message = made ? "Backed up." : "Today's backup already exists."
        } catch {
            model.message = error.localizedDescription
        }
        reload()
    }
}
