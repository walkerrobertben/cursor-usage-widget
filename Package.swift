// swift-tools-version: 5.9
import PackageDescription

#if os(macOS)
let appkitSources: [String] = []
#else
let appkitSources = [
    "StatusItemController.swift",
    "UsageMeterView.swift",
    "UsageModelRowView.swift",
    "UsagePoller.swift",
]
#endif

let package = Package(
    name: "CursorUsage",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "CursorUsageCore", targets: ["CursorUsageCore"]),
        .library(name: "CursorUsageHTML", targets: ["CursorUsageHTML"]),
        .executable(name: "CursorUsage", targets: ["CursorUsage"]),
    ],
    targets: [
        .target(
            name: "CursorUsageCore",
            path: "Sources/CursorUsageCore"
        ),
        .target(
            name: "CursorUsageHTML",
            dependencies: ["CursorUsageCore"],
            path: "Sources/CursorUsageHTML"
        ),
        .executableTarget(
            name: "CursorUsage",
            dependencies: ["CursorUsageCore"],
            path: "Sources/CursorUsage",
            exclude: appkitSources
        ),
        .testTarget(
            name: "CursorUsageTests",
            dependencies: ["CursorUsageCore", "CursorUsageHTML"],
            path: "Tests/CursorUsageTests",
            exclude: ["__pycache__"],
            resources: [
                .copy("Fixtures"),
                .copy("Snapshots"),
                .copy("snapshot_png.py"),
            ]
        ),
    ]
)
