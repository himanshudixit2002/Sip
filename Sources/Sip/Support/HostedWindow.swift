import AppKit
import Darwin
import SwiftUI

/// A standard window around a SwiftUI view. Sip has no Dock icon, so opening
/// one has to activate the app explicitly or it would appear behind
/// everything.
@MainActor
final class HostedWindow: NSObject, NSWindowDelegate {
    let window: NSWindow
    /// Called once the window has closed, so the owner can let go of it and
    /// the whole view tree is freed rather than kept around hidden.
    var onClose: (() -> Void)?

    init<Content: View>(title: String, size: NSSize, content: Content, resizable: Bool = true) {
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .fullSizeContentView]
        if resizable { style.insert(.resizable) }
        window = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: style,
                          backing: .buffered, defer: false)
        super.init()
        window.title = title
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = []
        window.contentViewController = controller
        window.setContentSize(size)
        window.minSize = NSSize(width: min(size.width, 560), height: min(size.height, 420))
        window.center()
        window.delegate = self
    }

    func windowWillClose(_ notification: Notification) {
        // Detach the content now; the owner drops this object next.
        DispatchQueue.main.async { [weak self] in
            self?.window.contentViewController = nil
            self?.onClose?()
            Memory.relieve()
        }
    }

    func present() {
        NSApp.activate()
        let opening = !window.isVisible
        window.makeKeyAndOrderFront(nil)
        if opening {
            // Open with nothing focused. Otherwise the first control (the
            // goal slider) gets a focus ring the moment the window appears.
            DispatchQueue.main.async { [weak self] in self?.window.makeFirstResponder(nil) }
        }
    }

    func close() { window.close() }
}

/// Measures Sip's own CPU and memory: one CSV row per interval, then quits.
/// Started by the `bench` debug hook. `SIP_BENCH_SECONDS` sets the length and
/// `SIP_BENCH_EVERY` the row interval, so a 30-minute soak prints one row a
/// minute. Memory is the physical footprint (what Activity Monitor shows),
/// not RSS, which drops right after memory is handed back and flatters.
@MainActor
enum Bench {
    static func start() {
        let env = ProcessInfo.processInfo.environment
        let seconds = Int(env["SIP_BENCH_SECONDS"] ?? "") ?? 30
        let every = max(Int(env["SIP_BENCH_EVERY"] ?? "") ?? 1, 1)
        var last = cpuTime()
        var lastWall = CFAbsoluteTimeGetCurrent()
        var elapsed = 0
        var samples: [Double] = []
        var peakFootprint = 0.0
        var lastFrames = LiquidLayerView.framesDrawn
        print("second,cpu_percent_of_core,fps,ms_per_frame,footprint_mb")
        fflush(stdout)
        let timer = Timer(timeInterval: Double(every), repeats: true) { timer in
            let cpu = cpuTime()
            let wall = CFAbsoluteTimeGetCurrent()
            let interval = max(wall - lastWall, 0.001)
            let percent = (cpu - last) / interval * 100
            last = cpu
            lastWall = wall
            elapsed += every
            // The first seconds include launch work.
            if elapsed > 2 { samples.append(percent) }
            let frames = LiquidLayerView.framesDrawn - lastFrames
            lastFrames = LiquidLayerView.framesDrawn
            let fps = Double(frames) / interval
            let msPerFrame = frames > 0 ? percent * interval * 10 / Double(frames) : 0
            let footprint = Memory.footprintMB()
            if elapsed > 2 { peakFootprint = max(peakFootprint, footprint) }
            print(String(format: "%d,%.2f,%.0f,%.2f,%.1f", elapsed, percent, fps, msPerFrame, footprint)
                  + " " + LiquidLayerView.lastDecision)
            fflush(stdout)
            if elapsed >= seconds {
                timer.invalidate()
                let mean = samples.isEmpty ? 0 : samples.reduce(0, +) / Double(samples.count)
                print(String(format: "BENCH_MEAN %.2f", mean))
                print(String(format: "BENCH_FOOTPRINT %.1f peak %.1f", footprint, peakFootprint))
                print("BENCH_DONE")
                fflush(stdout)
                NSApp.terminate(nil)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    nonisolated private static func cpuTime() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
        let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
        return user + system
    }
}

/// Process memory helpers.
enum Memory {
    /// Physical footprint in MB, the number Activity Monitor reports.
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : 0
    }

    /// Hands freed heap pages back to the system.
    static func relieve() { malloc_zone_pressure_relief(nil, 0) }
}
