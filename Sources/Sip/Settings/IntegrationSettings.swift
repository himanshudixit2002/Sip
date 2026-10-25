import AppKit
import SwiftUI
import SipCore

// MARK: - Sync & iPhone

struct IntegrationSettings: View {
    let state: AppState
    @Bindable var settings: SettingsStore
    @StateObject private var copied = Box<String?>(nil)

    private static let steps = """
    1. On your iPhone, open Shortcuts and tap + to make a shortcut. Name it “Log Water”.
    2. Add “Ask for Input”. Set it to Number and the prompt to “How much (ml)?”.
    3. Add “Append to Text File”. Text: Provided Input. File path: Sip Inbox.txt. It saves to iCloud Drive › Shortcuts.
    4. Optional, for Apple Health: add “Log Health Sample”. Type: Water. Value: Provided Input. Unit: mL.
    5. Add the shortcut to your Home Screen, Lock Screen or Action button.
    Sip picks up each line within a few seconds. A line can also say “330 tea” or “2 glasses”.
    """

    private static let links: [(String, String)] = [
        ("sip://log?ml=250", "Log 250 ml of your default drink"),
        ("sip://log?ml=330&drink=tea", "Log 330 ml of tea"),
        ("sip://log?text=2%20glasses", "Log anything the quick-log box understands"),
        ("sip://refill", "Log one full bottle"),
        ("sip://undo", "Remove the last drink"),
        ("sip://quicklog", "Open the quick-log box"),
        ("sip://peek", "Bring the widget above your windows"),
        ("sip://toggle", "Show or hide the widget (also show, hide)"),
        ("sip://log?cup=Glass", "Log one of your cups by name"),
        ("sip://insights", "Open Insights (also settings)"),
        ("sip://share", "Save this week's card"),
    ]

    var body: some View {
        Form {
            Section {
                ForEach(["“Log water in Sip”", "“Log a coffee in Sip”", "“How much have I drunk in Sip?”", "“Undo my last drink in Sip”"],
                        id: \.self) { phrase in
                    Label(phrase, systemImage: "waveform")
                }
                HStack {
                    Button("Open Shortcuts") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Shortcuts.app"))
                    }
                    Button("Focus Settings…") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.Focus-Settings.extension") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
            } header: {
                Text("Siri, Shortcuts and Spotlight")
            } footer: {
                FooterText("Sip's actions are in the Shortcuts app (log a drink or a cup, undo, finished my bottle, today's progress, bring the widget forward), and Siri and Spotlight know the phrases above. In System Settings → Focus, add Sip's Focus filter to a Focus to pause reminders and the HUD while it's on.")
            }

            CommandLineSection()

            Section {
                Toggle("Keep history in iCloud Drive", isOn: $settings.iCloudSync)
                    .disabled(SipPaths.iCloudDrive == nil)
                if SipPaths.iCloudDrive == nil {
                    Label("iCloud Drive isn't turned on for this Mac.", systemImage: "icloud.slash")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Sync between Macs")
            } footer: {
                FooterText("Every Mac running Sip with this switched on shares one history. Changes from each Mac are merged, and a drink deleted on one stays deleted on the others.")
            }

            Section {
                Toggle("Read the inbox", isOn: $settings.inboxEnabled)
                ForEach(SipPaths.inboxFiles(iCloud: settings.iCloudSync), id: \.self) { file in
                    HStack {
                        Image(systemName: FileManager.default.fileExists(atPath: file.path) ? "doc.text.fill" : "doc.text")
                            .foregroundStyle(.secondary)
                        Text(file.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(.caption.monospaced())
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Button("Show") {
                            if !FileManager.default.fileExists(atPath: file.path) {
                                try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
                                try? "".write(to: file, atomically: true, encoding: .utf8)
                            }
                            NSWorkspace.shared.activateFileViewerSelecting([file])
                        }
                    }
                }
                Text(Self.steps)
                    .font(.callout)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Copy These Steps") { copy(Self.steps, "steps") }
                    if copied.value == "steps" { Text("Copied").foregroundStyle(.secondary) }
                }
                if SipPaths.shortcutsFolder == nil {
                    Label("The Shortcuts folder appears in iCloud Drive once Shortcuts on any of your devices has saved a file there.",
                          systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Log from your iPhone (and Apple Health)")
            } footer: {
                FooterText("Each line in an inbox file is logged, then the file is emptied. Sip watches the folders with file-system events, so this costs nothing while nothing changes.")
            }

            Section {
                ForEach(Self.links, id: \.0) { link in
                    HStack {
                        Text(link.0.removingPercentEncoding ?? link.0)
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                        Spacer()
                        Text(link.1).font(.caption).foregroundStyle(.secondary)
                        Button {
                            copy(link.0, link.0)
                        } label: {
                            Image(systemName: copied.value == link.0 ? "checkmark" : "doc.on.doc")
                        }
                        .buttonStyle(.borderless)
                        .help("Copy")
                    }
                }
            } header: {
                Text("Links")
            } footer: {
                FooterText("Use these from Shortcuts on your Mac, Raycast, Alfred, a Stream Deck, or Terminal (open \"sip://refill\").")
            }
        }
    }

    private func copy(_ text: String, _ tag: String) {
        Clipboard.copy(text)
        copied.value = tag
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { if copied.value == tag { copied.value = nil } }
    }
}


/// The `sip` command and Raycast script commands.
private struct CommandLineSection: View {
    @StateObject private var installed = Box(CLIInstaller.isInstalled)
    @StateObject private var message = Box<String?>(nil)

    var body: some View {
        Section {
            HStack {
                Label(installed.value ? "Installed at ~/.local/bin/sip" : "Not installed",
                      systemImage: installed.value ? "checkmark.circle.fill" : "terminal")
                    .foregroundStyle(installed.value ? Color.green : Color.secondary)
                Spacer()
                if installed.value {
                    Button("Remove") {
                        CLIInstaller.uninstall()
                        installed.value = CLIInstaller.isInstalled
                    }
                } else {
                    Button("Install") {
                        message.value = CLIInstaller.install()
                        installed.value = CLIInstaller.isInstalled
                    }
                    .disabled(!CLIInstaller.helperExists)
                }
            }
            Text("sip log 330 tea   ·   sip status   ·   sip undo   ·   sip refill   ·   sip peek")
                .font(.callout.monospaced())
                .textSelection(.enabled)
            HStack {
                Button("Create Raycast Commands") {
                    if let folder = CLIInstaller.writeRaycastCommands() {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                        message.value = "In Raycast: Settings → Extensions → Script Commands → Add Directories, and pick this folder."
                    }
                }
                .disabled(!installed.value)
            }
            if let text = message.value {
                Text(text).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Command line and Raycast")
        } footer: {
            FooterText("The command talks to the running app and never brings it forward. `sip status --json` prints today's numbers for scripts.")
        }
    }
}
