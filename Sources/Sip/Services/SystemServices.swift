import AppKit
import ServiceManagement

enum Haptics {
    static func levelChange() {
        NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
    }
}

/// Launch at login via `SMAppService`. The service can refuse an ad-hoc signed
/// app, so every call reports what actually happened.
enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static var statusText: String {
        switch SMAppService.mainApp.status {
        case .enabled: return "Sip opens when you log in."
        case .requiresApproval: return "Waiting for approval in System Settings → General → Login Items."
        case .notFound: return "macOS couldn't find this copy of Sip. Move it to Applications and try again."
        case .notRegistered: return "Off."
        @unknown default: return "Unknown state."
        }
    }

    /// Returns an error message, or nil on success.
    @discardableResult
    static func set(_ enabled: Bool) -> String? {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
