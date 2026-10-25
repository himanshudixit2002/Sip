import AppKit
import SwiftUI

/// `@State` is a macro in the current SDK and SwiftUI's macro plugin ships only
/// with Xcode, so view-local state lives in these small boxes held by
/// `@StateObject` instead.
final class Box<Value>: ObservableObject {
    @Published var value: Value
    init(_ value: Value) { self.value = value }
}

/// Environment keys written out by hand for the same reason `@Entry` can't be used.
private struct AnimationsPausedKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while the window hosting a view is hidden, so animated views can
    /// stop their timelines.
    var animationsPaused: Bool {
        get { self[AnimationsPausedKey.self] }
        set { self[AnimationsPausedKey.self] = newValue }
    }
}

/// A button style that dips on press, for quick-add cups and pills.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.93

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? 0.08 : 0)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// An `NSMenuItem` that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, key: String = "", state: NSControl.StateValue = .off,
         enabled: Bool = true, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: key)
        self.target = self
        self.state = state
        self.isEnabled = enabled
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { handler() }
}
