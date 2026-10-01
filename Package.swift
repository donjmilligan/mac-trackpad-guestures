// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "GestureKeys",
    platforms: [.macOS(.v14)],
    targets: [
        // Thin C bridge that dlopens Apple's private MultitouchSupport.framework.
        .target(name: "CMultitouch"),
        // Pure gesture logic (no AppKit) so it can be exercised by SelfTest.
        .target(name: "GestureCore"),
        .executableTarget(name: "GestureKeys", dependencies: ["CMultitouch", "GestureCore"]),
        // Command Line Tools ship neither XCTest nor Swift Testing, so tests are a plain executable.
        .executableTarget(name: "SelfTest", dependencies: ["GestureCore"]),
    ],
    swiftLanguageModes: [.v5]
)
