import Foundation

/// Switches read from `SIP_DEBUG`, a comma-separated list such as
/// `SIP_DEBUG=demo,pour,size=l`. They exist so every screen and animation can
/// be checked from a shell without touching saved data.
enum DebugHooks {
    private static let raw: [String: String] = {
        let value = ProcessInfo.processInfo.environment["SIP_DEBUG"] ?? ""
        var result: [String: String] = [:]
        for item in value.split(separator: ",") {
            let parts = item.split(separator: "=", maxSplits: 1).map { String($0).trimmingCharacters(in: .whitespaces) }
            guard let key = parts.first, !key.isEmpty else { continue }
            result[key.lowercased()] = parts.count > 1 ? parts[1] : ""
        }
        return result
    }()

    static func has(_ key: String) -> Bool { raw[key] != nil }
    static func value(_ key: String) -> String? { raw[key] }

    /// 60 days of made-up history, held in memory only.
    static var demo: Bool { has("demo") }
    /// Pour automatically every few seconds.
    static var autoPour: Bool { has("pour") }
    static var celebrate: Bool { has("celebrate") }
    static var diagnostics: Bool { has("diagnostics") }
    static var bench: Bool { has("bench") }
    static var popover: Bool { has("popover") }
    static var insights: Bool { has("insights") }
    static var onboarding: Bool { has("onboarding") }
    static var settingsTab: String? { value("settings") }
    static var size: String? { value("size") }
    static var appearance: String? { has("light") ? "light" : (has("dark") ? "dark" : nil) }
    static var style: String? { value("style") }
    static var theme: String? { value("theme") }
    static var background: String? { value("background") }

    /// Settings for this run. A run with `SIP_DATA_DIR` (a test) keeps its
    /// settings in a separate domain, so nothing clicked or changed while
    /// testing touches your real ones.
    static let defaults: UserDefaults = {
        guard dataDirectory != nil, let scratch = UserDefaults(suiteName: scratchDomain) else { return .standard }
        return scratch
    }()

    static let scratchDomain = "com.himanshudixit.sip.scratch"

    /// The domain `defaults` saves to.
    static var defaultsDomain: String {
        dataDirectory != nil ? scratchDomain : (Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName)
    }

    /// Overrides where history is read and written.
    static var dataDirectory: URL? {
        ProcessInfo.processInfo.environment["SIP_DATA_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
}

/// Counts view-body evaluations when `bodycount` is on, printing a summary
/// every two seconds. For finding views that re-render too often.
enum BodyCounter {
    nonisolated(unsafe) private static var counts: [String: Int] = [:]
    nonisolated(unsafe) private static var started = false

    static func hit(_ name: String) {
        guard DebugHooks.has("bodycount") else { return }
        counts[name, default: 0] += 1
        guard !started else { return }
        started = true
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            print("bodies: " + counts.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " "))
            fflush(stdout)
            counts.removeAll()
        }
    }
}
