// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Still",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Still", targets: ["Still"]),
        .library(name: "StillCore", targets: ["StillCore"]),
    ],
    targets: [
        // Persistence, task operations, visibility rules. No UI. Shared by the
        // app today and by future integrations (App Intents, CLI, MCP).
        .target(
            name: "StillCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        // The macOS application: AppKit lifecycle and windows, SwiftUI views.
        .executableTarget(
            name: "Still",
            dependencies: ["StillCore"],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        ),
        .testTarget(
            name: "StillCoreTests",
            dependencies: ["StillCore"]
        ),
    ]
)
