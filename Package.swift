// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIAgentPM",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "mcp-server-pm", targets: ["MCPServer"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0")
    ],
    targets: [
        // Domain層（共有）
        .target(
            name: "Domain",
            dependencies: []
        ),
        // Infrastructure層（共有）
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        // MCPサーバー
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                "Domain",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        )
    ]
)
