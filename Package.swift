// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipboardHistory",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic (no AppKit): capture filtering, storage, search. Unit tested.
        .target(name: "ClipboardCore"),
        // The menu bar app itself.
        .executableTarget(
            name: "ClipboardHistory",
            dependencies: ["ClipboardCore"],
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
    ],
    swiftLanguageModes: [.v5]
)
