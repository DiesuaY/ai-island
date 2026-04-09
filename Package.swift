// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIIsland",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "AIIsland", targets: ["AIIsland"]),
        .executable(name: "aibridge", targets: ["AIBridge"]),
        .library(name: "AIIslandProtocol", targets: ["AIIslandProtocol"]),
    ],
    targets: [
        .executableTarget(
            name: "AIIsland",
            dependencies: ["AIIslandProtocol"],
            path: "Sources/AIIsland"
        ),
        .executableTarget(
            name: "AIBridge",
            dependencies: ["AIIslandProtocol"],
            path: "Sources/AIBridge"
        ),
        .target(
            name: "AIIslandProtocol",
            path: "Sources/AIIslandProtocol"
        ),
        .testTarget(
            name: "AIIslandTests",
            dependencies: ["AIIslandProtocol"]
        ),
        .testTarget(
            name: "AIBridgeTests",
            dependencies: ["AIIslandProtocol"]
        ),
    ]
)
