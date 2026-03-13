// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexXPCBridge",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "CodexBridgeContract", targets: ["CodexBridgeContract"]),
        .library(name: "CodexBridgeSupport", targets: ["CodexBridgeSupport"]),
        .library(name: "CodexBridgeXPC", targets: ["CodexBridgeXPC"]),
        .library(name: "CodexBridgeServiceCore", targets: ["CodexBridgeServiceCore"]),
        .executable(name: "CodexXPCBridgeDemo", targets: ["CodexXPCBridgeDemo"]),
        .executable(name: "CodexXPCBridgeService", targets: ["CodexXPCBridgeService"]),
        .executable(name: "codex", targets: ["codex"]),
    ],
    targets: [
        .target(
            name: "CodexBridgeContract",
            path: "Sources/CodexBridgeContract"
        ),
        .target(
            name: "CodexBridgeSupport",
            dependencies: ["CodexBridgeContract"],
            path: "Sources/CodexBridgeSupport"
        ),
        .target(
            name: "CodexBridgeXPC",
            dependencies: ["CodexBridgeContract"],
            path: "Sources/CodexBridgeXPC"
        ),
        .target(
            name: "CodexBridgeServiceCore",
            dependencies: [
                "CodexBridgeContract",
                "CodexBridgeSupport",
                "CodexBridgeXPC",
            ],
            path: "Sources/CodexBridgeServiceCore"
        ),
        .executableTarget(
            name: "CodexXPCBridgeDemo",
            dependencies: [
                "CodexBridgeContract",
                "CodexBridgeSupport",
                "CodexBridgeXPC",
            ],
            path: "Sources/CodexBridgeApp"
        ),
        .executableTarget(
            name: "CodexXPCBridgeService",
            dependencies: [
                "CodexBridgeContract",
                "CodexBridgeSupport",
                "CodexBridgeXPC",
                "CodexBridgeServiceCore",
            ],
            path: "Sources/CodexBridgeService"
        ),
        .executableTarget(
            name: "codex",
            dependencies: ["CodexBridgeContract"],
            path: "Sources/codex"
        ),
        .testTarget(
            name: "CodexBridgeContractTests",
            dependencies: ["CodexBridgeContract"],
            path: "Tests/CodexBridgeContractTests"
        ),
        .testTarget(
            name: "CodexBridgeSupportTests",
            dependencies: ["CodexBridgeContract", "CodexBridgeSupport"],
            path: "Tests/CodexBridgeSupportTests"
        ),
        .testTarget(
            name: "CodexBridgeServiceCoreTests",
            dependencies: [
                "CodexBridgeContract",
                "CodexBridgeSupport",
                "CodexBridgeXPC",
                "CodexBridgeServiceCore",
            ],
            path: "Tests/CodexBridgeServiceCoreTests"
        ),
    ]
)
