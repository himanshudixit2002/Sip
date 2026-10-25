import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Small shared pieces that used to be written out in several places.

/// The few colours that mean something, so "goal reached" is the same green
/// everywhere.
enum Palette {
    static let goal = Color(hex: 0x4BE38B)
    static let goalDeep = Color(hex: 0x1FA866)
    static let freeze = Color(hex: 0x8FE3FF)
    static let gold = Color(hex: 0xFFC233)
    static let badge = Color(hex: 0xFFD25A)
    static let warning = Color(hex: 0xFFB347)
    static let caffeine = Color(hex: 0xC9A7FF)
    static let night = Color(hex: 0x0A1122)
    static let nightTop = Color(hex: 0x16233F)
}

/// Runs the latest scheduled block once things have been quiet for a while.
struct Debouncer {
    private var work: DispatchWorkItem?

    mutating func schedule(after seconds: Double, _ block: @escaping () -> Void) {
        work?.cancel()
        let item = DispatchWorkItem(block: block)
        work = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    mutating func cancel() {
        work?.cancel()
        work = nil
    }
}

/// Other apps' on-screen windows, from the window server. Bounds and owners
/// need no Screen Recording permission.
struct WindowInfo {
    var ownerPID: pid_t
    var ownerName: String
    var layer: Int
    var alpha: Double
    /// Top-left origin, as the window server reports it.
    var bounds: CGRect
}

enum WindowList {
    /// Windows above `windowID` (or all on-screen windows when nil), front to back.
    static func onScreen(above windowID: CGWindowID? = nil) -> [WindowInfo] {
        let options: CGWindowListOption = windowID == nil ? [.optionOnScreenOnly, .excludeDesktopElements]
                                                          : [.optionOnScreenAboveWindow]
        guard let list = CGWindowListCopyWindowInfo(options, windowID ?? kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { window in
            guard let b = window[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? Double, let y = b["Y"] as? Double,
                  let w = b["Width"] as? Double, let h = b["Height"] as? Double else { return nil }
            return WindowInfo(ownerPID: window[kCGWindowOwnerPID as String] as? pid_t ?? 0,
                              ownerName: window[kCGWindowOwnerName as String] as? String ?? "",
                              layer: window[kCGWindowLayer as String] as? Int ?? 0,
                              alpha: window[kCGWindowAlpha as String] as? Double ?? 1,
                              bounds: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}

/// Save and open panels. Sip has no Dock icon, so it has to come forward first
/// or the panel opens behind everything.
@MainActor
enum Modal {
    static func save(name: String, types: [UTType], _ write: (URL) throws -> Void) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = types
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try write(url)
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSSound.beep()
        }
    }

    static func open(types: [UTType]) -> URL? {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = false
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func chooseFolder(prompt: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = prompt
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
}

enum Clipboard {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    static func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}

/// Renders a SwiftUI view to a bitmap.
@MainActor
func renderCGImage<V: View>(_ view: V, size: CGSize? = nil, scale: CGFloat) -> CGImage? {
    let renderer = ImageRenderer(content: view)
    if let size { renderer.proposedSize = ProposedViewSize(size) }
    renderer.scale = scale
    return renderer.cgImage
}

extension NSPanel {
    /// A borderless, see-through panel that never asks to be the main window.
    func configureTransparent(level: NSWindow.Level, shadow: Bool) {
        isOpaque = false
        backgroundColor = .clear
        hasShadow = shadow
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        self.level = level
    }

    /// Centred horizontally, a quarter of the way down the main screen.
    func positionTopCenter(fromTop share: CGFloat = 0.24) {
        guard let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        setFrameOrigin(NSPoint(x: f.midX - frame.width / 2, y: f.maxY - f.height * share - frame.height / 2))
    }
}

extension URL {
    /// The path with the home folder shown as `~`.
    var abbreviatedPath: String { (path as NSString).abbreviatingWithTildeInPath }
}

extension Double {
    /// 0.534 → 53
    var percent: Int { Int((self * 100).rounded()) }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// "Stored at ~/… [Show]".
struct FileRow: View {
    var title: String
    var url: URL

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Text(url.abbreviatedPath)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
                Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    .controlSize(.small)
            }
        }
    }
}
