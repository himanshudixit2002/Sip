import Foundation

/// A parsed `sip` command. Parsing does no I/O, so the tool's whole command
/// surface can be tested here; the tool itself only opens URLs and reads the
/// status file.
public enum CLICommand: Equatable, Sendable {
    /// Log a drink described in quick-log words: "330 tea", "glass".
    case log(String)
    case status(json: Bool)
    case undo
    case refill
    /// Show the widget for a moment.
    case peek
    /// Open the quick-log box.
    case quickLog
    /// "settings" or "insights".
    case open(String)
    case help
    case version

    public static let scheme = "sip"
    public static let openTargets = ["settings", "insights"]

    /// Parses arguments, not including the program name.
    ///
    /// - No arguments means `status`.
    /// - Anything starting with a number logs it: `sip 330 tea`.
    /// - `settings` and `insights` work on their own as well as after `open`.
    public static func parse(_ args: [String]) -> Result<CLICommand, CLIError> {
        let args = args.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = args.first else { return .success(.status(json: false)) }
        let rest = Array(args.dropFirst())
        let name = first.lowercased()

        func noArguments(_ command: CLICommand) -> Result<CLICommand, CLIError> {
            rest.isEmpty ? .success(command) : .failure(.unexpectedArgument(command: name, argument: rest[0]))
        }

        switch name {
        case "log", "add":
            let text = rest.joined(separator: " ")
            return text.isEmpty ? .failure(.missingText) : .success(.log(text))
        case "status", "--json", "-j":
            var json = name != "status"
            for option in rest {
                switch option.lowercased() {
                case "--json", "-j": json = true
                default: return .failure(.unknownOption(option))
                }
            }
            return .success(.status(json: json))
        case "undo": return noArguments(.undo)
        case "refill": return noArguments(.refill)
        case "peek": return noArguments(.peek)
        case "quicklog", "quick-log", "ql": return noArguments(.quickLog)
        case "settings", "insights": return noArguments(.open(name))
        case "open":
            guard let target = rest.first?.lowercased() else { return .failure(.missingTarget) }
            guard openTargets.contains(target) else { return .failure(.unknownTarget(target)) }
            return rest.count == 1 ? .success(.open(target))
                                   : .failure(.unexpectedArgument(command: name, argument: rest[1]))
        case "help", "-h", "--help": return .success(.help)
        case "version", "-v", "--version": return .success(.version)
        default:
            if let c = first.first, c.isNumber || (c == "." && first.dropFirst().first?.isNumber == true) {
                return .success(.log(args.joined(separator: " ")))
            }
            return first.hasPrefix("-") ? .failure(.unknownOption(first)) : .failure(.unknownCommand(first))
        }
    }

    /// The app URL that carries out the command, or nil for commands the tool
    /// answers itself (status, help, version).
    public var url: URL? {
        switch self {
        case .log(let text): return URL(string: "\(Self.scheme)://log?text=\(Self.percentEncode(text))")
        case .undo: return URL(string: "\(Self.scheme)://undo")
        case .refill: return URL(string: "\(Self.scheme)://refill")
        case .peek: return URL(string: "\(Self.scheme)://peek")
        case .quickLog: return URL(string: "\(Self.scheme)://quicklog")
        case .open(let target):
            return Self.openTargets.contains(target) ? URL(string: "\(Self.scheme)://\(target)") : nil
        case .status, .help, .version: return nil
        }
    }

    /// Everything except unreserved characters is escaped, including `+` and
    /// `&`, so the text survives any query parser.
    static func percentEncode(_ text: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        // `alphanumerics` includes non-ASCII letters; escape those too.
        return text.unicodeScalars.map { scalar -> String in
            if scalar.isASCII, allowed.contains(scalar) { return String(scalar) }
            return String(scalar).utf8.map { String(format: "%%%02X", $0) }.joined()
        }.joined()
    }

    public static let helpText = """
    sip: log water and check today's progress from the terminal.

    Usage:
      sip                     Today's progress (same as `sip status`)
      sip <amount> [drink]    Log a drink, e.g. `sip 330`, `sip 500 ml tea`, `sip 1.5l`
      sip log <text>          Log anything the quick-log box understands, e.g. `sip log glass`
      sip status [--json]     Today's progress, or the full status as JSON
      sip undo                Remove the last drink
      sip refill              Log a full bottle
      sip peek                Show the widget for a moment
      sip quicklog            Open the quick-log box
      sip open settings       Open Settings (also: sip settings)
      sip open insights       Open Insights (also: sip insights)
      sip help                This help
      sip version             The version number
    """
}

public enum CLIError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingText
    case missingTarget
    case unknownTarget(String)
    case unknownCommand(String)
    case unknownOption(String)
    case unexpectedArgument(command: String, argument: String)

    /// A one-line message saying what went wrong and what to type instead.
    public var description: String {
        switch self {
        case .missingText:
            return "Say what to log, e.g. `sip log 330 tea` or `sip log glass`."
        case .missingTarget:
            return "Say what to open: `sip open settings` or `sip open insights`."
        case .unknownTarget(let target):
            return "Can't open '\(target)'. Try `sip open settings` or `sip open insights`."
        case .unknownCommand(let command):
            return "Unknown command '\(command)'. To log a drink start with an amount (`sip 330 tea`) or use `sip log \(command)`. See `sip help`."
        case .unknownOption(let option):
            return "Unknown option '\(option)'. See `sip help`."
        case .unexpectedArgument(let command, let argument):
            return "`sip \(command)` doesn't take '\(argument)'. See `sip help`."
        }
    }
}
