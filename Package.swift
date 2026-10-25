// swift-tools-version: 6.0
import PackageDescription

// The app itself is built by Sip.xcodeproj (it needs Xcode for App Intents).
// This package holds what can be built and tested from a shell: the pure
// logic, its tests, and the `sip` command-line helper.
let package = Package(
    name: "Sip",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "SipCore", targets: ["SipCore"]),
        .executable(name: "sip", targets: ["SipCLI"])
    ],
    targets: [
        // Pure logic: days, streaks, pace, reminder planning, persistence.
        // Kept free of AppKit and SwiftUI so it can be tested from a shell.
        .target(
            name: "SipCore",
            path: "Sources/SipCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // `sip log 330 tea`: a small command that hands work to the running
        // app through sip:// links. Shipped inside Sip.app/Contents/Helpers.
        .executableTarget(
            name: "SipCLI",
            dependencies: ["SipCore"],
            path: "Sources/SipCLI",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "SipCoreTests",
            dependencies: ["SipCore"],
            path: "Tests/SipCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
