import Foundation

/// Every folder and file Sip reads or writes, in one place so the app, the
/// widget and the `sip` command line tool agree.
///
/// - **Local** (default): `~/Library/Application Support/Sip/history.json`.
/// - **iCloud Drive**: `iCloud Drive/Sip/history.json`, shared by every Mac
///   signed in to the same account.
/// - **Inbox**: a plain text file anything can append lines to, most usefully
///   an iPhone Shortcut. It lives in `iCloud Drive/Shortcuts/Sip Inbox.txt`
///   (where the Shortcuts app saves by default) or `iCloud Drive/Sip/Inbox.txt`.
///
/// Paths start from the real home folder (from the user database, not the
/// sandbox), so a sandboxed widget and the unsandboxed app see the same files.
/// Setting `SIP_DATA_DIR` moves history, the inbox and backups into that
/// folder, so a debug run never touches saved data.
public enum SipPaths {
    /// Environment variable that overrides where data is read and written.
    public static let dataDirectoryVariable = "SIP_DATA_DIR"
    public static let historyFileName = "history.json"
    public static let statusFileName = "status.json"

    /// The user's real home folder, even inside a sandbox.
    public static var home: URL {
        if let entry = getpwuid(getuid()), let dir = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: dir), isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
    }

    /// The `SIP_DATA_DIR` folder, if set. An empty value counts as unset.
    public static var dataDirectoryOverride: URL? {
        dataDirectoryOverride(environment: ProcessInfo.processInfo.environment)
    }

    /// iCloud Drive's root, or nil when iCloud Drive is off on this Mac.
    public static var iCloudDrive: URL? { iCloudDrive(home: home) }

    /// The Shortcuts app's iCloud folder ("iCloud Drive/Shortcuts").
    public static var shortcutsFolder: URL? { shortcutsFolder(home: home) }

    /// `~/Library/Application Support/Sip`, ignoring any override.
    public static var localFolder: URL { localFolder(home: home) }

    /// `iCloud Drive/Sip`, or nil when iCloud Drive is off.
    public static var iCloudFolder: URL? { iCloudDrive?.appendingPathComponent("Sip", isDirectory: true) }

    /// Where history is kept: the override, else iCloud Drive when asked for
    /// and available, else the local folder.
    public static func dataFolder(iCloud: Bool) -> URL {
        dataFolder(iCloud: iCloud, home: home, environment: ProcessInfo.processInfo.environment)
    }

    /// Every inbox file Sip reads.
    public static func inboxFiles(iCloud: Bool) -> [URL] {
        inboxFiles(iCloud: iCloud, home: home, environment: ProcessInfo.processInfo.environment)
    }

    /// `~/Library/Application Support/Sip/status.json`, written by the app for
    /// the command line tool. Always this fixed path so the tool can find it.
    public static var statusFile: URL { localFolder.appendingPathComponent(statusFileName) }

    /// `~/Library/Application Support/Sip/Backups`. Backups are per Mac, so
    /// they stay local even when history syncs; under `SIP_DATA_DIR` they go
    /// in that folder instead, next to the history they copy.
    public static var backupsFolder: URL {
        backupsFolder(home: home, environment: ProcessInfo.processInfo.environment)
    }

    // MARK: - Testable forms

    static func dataDirectoryOverride(environment: [String: String]) -> URL? {
        guard let path = environment[dataDirectoryVariable], !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    static func iCloudDrive(home: URL) -> URL? {
        existing(home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true))
    }

    static func shortcutsFolder(home: URL) -> URL? {
        existing(home.appendingPathComponent(
            "Library/Mobile Documents/iCloud~is~workflow~my~workflows/Documents", isDirectory: true))
    }

    static func localFolder(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Sip", isDirectory: true)
    }

    static func dataFolder(iCloud: Bool, home: URL, environment: [String: String]) -> URL {
        if let override = dataDirectoryOverride(environment: environment) { return override }
        if iCloud, let drive = iCloudDrive(home: home) { return drive.appendingPathComponent("Sip", isDirectory: true) }
        return localFolder(home: home)
    }

    static func inboxFiles(iCloud: Bool, home: URL, environment: [String: String]) -> [URL] {
        if let override = dataDirectoryOverride(environment: environment) {
            return [override.appendingPathComponent("Inbox.txt")]
        }
        var files = [localFolder(home: home).appendingPathComponent("Inbox.txt")]
        if let folder = shortcutsFolder(home: home) { files.append(folder.appendingPathComponent("Sip Inbox.txt")) }
        if let drive = iCloudDrive(home: home) {
            files.append(drive.appendingPathComponent("Sip", isDirectory: true).appendingPathComponent("Inbox.txt"))
        }
        return files
    }

    static func backupsFolder(home: URL, environment: [String: String]) -> URL {
        let base = dataDirectoryOverride(environment: environment) ?? localFolder(home: home)
        return base.appendingPathComponent("Backups", isDirectory: true)
    }

    private static func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
