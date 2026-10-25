import Foundation
import SipCore

/// `sip://` links, so Shortcuts, Raycast, Alfred, a Stream Deck button or a
/// terminal can drive Sip:
///
/// | Link | Does |
/// |---|---|
/// | `sip://log?ml=330&drink=tea` | logs 330 ml of tea (`oz=12` also works) |
/// | `sip://log?text=2 glasses` | anything the quick-log box understands |
/// | `sip://log?cup=Glass` | a quick-add cup by name |
/// | `sip://refill` | logs one full bottle |
/// | `sip://undo` | removes the last drink |
/// | `sip://quicklog` | opens the quick-log box |
/// | `sip://peek` | brings the widget above your windows for a moment |
/// | `sip://show`, `sip://hide`, `sip://toggle` | the widget |
/// | `sip://settings`, `sip://insights` | opens that window |
/// | `sip://share` | saves this week's card |
enum URLAction: Equatable {
    case log(ml: Double, drink: DrinkKind?)
    case logText(String)
    case logCup(String)
    case command(SipCommand)
    case widget(Bool?)

    init?(_ url: URL) {
        guard url.scheme?.lowercased() == "sip" else { return nil }
        let command = (url.host ?? url.path).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var query: [String: String] = [:]
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            query[item.name.lowercased()] = item.value
        }
        switch command {
        case "log", "add", "drink":
            let drink = query["drink"].flatMap { DrinkKind(rawValue: $0.lowercased()) }
            if let ml = query["ml"].flatMap(Double.init), ml > 0 {
                self = .log(ml: ml, drink: drink)
            } else if let oz = query["oz"].flatMap(Double.init), oz > 0 {
                self = .log(ml: Volume.fromDisplay(oz, .fluidOunces), drink: drink)
            } else if let cup = query["cup"] {
                self = .logCup(cup)
            } else if let text = query["text"] ?? query["q"] {
                self = .logText(text)
            } else {
                self = .logCup("")   // the default cup
            }
        case "refill", "bottle": self = .command(.refill)
        case "undo": self = .command(.undo)
        case "quicklog", "quick": self = .command(.quickLog)
        case "peek": self = .command(.peek)
        case "show": self = .widget(true)
        case "hide": self = .widget(false)
        case "toggle": self = .widget(nil)
        case "settings", "preferences": self = .command(.settings)
        case "insights", "stats": self = .command(.insights)
        case "share": self = .command(.share)
        default: return nil
        }
    }
}
