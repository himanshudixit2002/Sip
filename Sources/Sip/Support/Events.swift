import Foundation
import SipCore

/// Animation cues broadcast to every bottle on screen: the widget, the menu
/// bar popover and the Settings previews each run their own simulation, and
/// all of them should react to a pour.
enum SipEvents {
    /// userInfo: `fraction` (Double, of the goal), `drink` (DrinkKind raw value)
    static let pour = Notification.Name("SipPour")
    static let celebrate = Notification.Name("SipCelebrate")
    static let wobble = Notification.Name("SipWobble")
    static let drain = Notification.Name("SipDrain")
    /// object: the window; userInfo: `dvx`, `dvy` (change in velocity, pt/s)
    static let windowMoved = Notification.Name("SipWindowMoved")

    static func post(_ name: Notification.Name, object: Any? = nil, _ info: [String: Any] = [:]) {
        NotificationCenter.default.post(name: name, object: object, userInfo: info)
    }

    static func pour(fraction: Double, drink: DrinkKind) {
        post(pour, ["fraction": fraction, "drink": drink.rawValue])
    }
}
