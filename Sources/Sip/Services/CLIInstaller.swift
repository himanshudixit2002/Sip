import AppKit
import SipCore

/// Puts the `sip` command on your PATH (a link in ~/.local/bin to the helper
/// inside the app) and writes Raycast script commands that use it.
enum CLIInstaller {
    static var helper: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/sip") }
    static var link: URL { SipPaths.home.appendingPathComponent(".local/bin/sip") }
    static var raycastFolder: URL { SipPaths.localFolder.appendingPathComponent("Raycast", isDirectory: true) }

    static var isInstalled: Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) == helper.path
    }

    static var helperExists: Bool { FileManager.default.isExecutableFile(atPath: helper.path) }

    /// Returns an error message, or nil.
    @discardableResult
    static func install() -> String? {
        guard helperExists else { return "This copy of Sip has no command-line helper. Rebuild it with ./build.sh." }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
                try fm.removeItem(at: link)
            }
            try fm.createSymbolicLink(at: link, withDestinationURL: helper)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    static func uninstall() {
        if isInstalled { try? FileManager.default.removeItem(at: link) }
    }

    /// Script commands for Raycast (Extensions → Script Commands → Add Directories).
    static func writeRaycastCommands() -> URL? {
        let fm = FileManager.default
        let scripts: [(String, String)] = [
            ("sip-log.sh", """
            #!/bin/bash
            # @raycast.schemaVersion 1
            # @raycast.title Log a Drink
            # @raycast.mode silent
            # @raycast.packageName Sip
            # @raycast.icon 💧
            # @raycast.argument1 { "type": "text", "placeholder": "330 tea, 2 glasses…" }
            "\(link.path)" log "$1"
            """),
            ("sip-status.sh", """
            #!/bin/bash
            # @raycast.schemaVersion 1
            # @raycast.title Sip Status
            # @raycast.mode inline
            # @raycast.refreshTime 5m
            # @raycast.packageName Sip
            # @raycast.icon 💧
            "\(link.path)" status
            """),
            ("sip-undo.sh", """
            #!/bin/bash
            # @raycast.schemaVersion 1
            # @raycast.title Undo Last Drink
            # @raycast.mode silent
            # @raycast.packageName Sip
            # @raycast.icon ↩️
            "\(link.path)" undo
            """),
            ("sip-refill.sh", """
            #!/bin/bash
            # @raycast.schemaVersion 1
            # @raycast.title Finished My Bottle
            # @raycast.mode silent
            # @raycast.packageName Sip
            # @raycast.icon 🫙
            "\(link.path)" refill
            """),
        ]
        do {
            try fm.createDirectory(at: raycastFolder, withIntermediateDirectories: true)
            for (name, body) in scripts {
                let url = raycastFolder.appendingPathComponent(name)
                try (body + "\n").write(to: url, atomically: true, encoding: .utf8)
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            return raycastFolder
        } catch {
            return nil
        }
    }
}
