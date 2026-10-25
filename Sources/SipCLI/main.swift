import Foundation
import SipCore

// The `sip` command. Logging and the other actions are passed to the running
// app as sip:// links, opened in the background so Sip never comes forward
// (and is started if it isn't running). `status` reads the numbers the app
// writes to ~/Library/Application Support/Sip/status.json.

let arguments = Array(CommandLine.arguments.dropFirst())

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

/// The Sip.app this command lives in, so links go to it and not to some
/// other app that also handles `sip:` (internet-phone apps do).
func hostApp() -> [String] {
    let exe = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath().path
    if let range = exe.range(of: ".app/Contents/Helpers/") {
        return ["-a", String(exe[..<range.lowerBound]) + ".app"]
    }
    return ["-b", "com.himanshudixit.sip"]
}

func openInBackground(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = ["-g"] + hostApp() + [url.absoluteString]
    do {
        try process.run()
        process.waitUntilExit()
    } catch {
        fail("sip: couldn't reach Sip (\(error.localizedDescription))")
    }
    if process.terminationStatus != 0 { fail("sip: Sip isn't installed in Applications?") }
}

switch CLICommand.parse(arguments) {
case .failure(let error):
    fail("sip: \(error)\n\n\(CLICommand.helpText)")
case .success(let command):
    switch command {
    case .help:
        print(CLICommand.helpText)
    case .version:
        print("sip 2.0")
    case .status(let json):
        guard let status = SipStatus.load(from: SipPaths.statusFile) else {
            fail("sip: no status yet. Open Sip, and check Settings → Siri, iPhone & More → Command line is installed.")
        }
        print(json ? status.json() : status.sentence())
    default:
        guard let url = command.url else { fail("sip: nothing to do") }
        openInBackground(url)
        if case .log = command {
            // Give the app a moment to log and write its status, then echo it.
            Thread.sleep(forTimeInterval: 2.6)
            if let status = SipStatus.load(from: SipPaths.statusFile), Date().timeIntervalSince(status.updated) < 10 {
                print(status.sentence())
            }
        }
    }
}
