// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeTrafficLight",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "ClaudeTrafficLight", targets: ["ClaudeTrafficLight"])
    ],
    targets: [
        .executableTarget(
            name: "ClaudeTrafficLight",
            path: "Sources/ClaudeTrafficLight"
        )
    ]
)
