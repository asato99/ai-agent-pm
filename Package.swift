// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIAgentPM",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "Domain", targets: ["Domain"]),
        .library(name: "UseCase", targets: ["UseCase"]),
        .library(name: "Infrastructure", targets: ["Infrastructure"]),
        .executable(name: "mcp-server-pm", targets: ["MCPServer"]),
        .executable(name: "AIAgentPM", targets: ["App"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.24.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/nalexn/ViewInspector.git", from: "0.10.0")
    ],
    targets: [
        // Domain層（エンティティ、値オブジェクト、リポジトリプロトコル）
        .target(
            name: "Domain",
            dependencies: []
        ),
        .testTarget(
            name: "DomainTests",
            dependencies: ["Domain"]
        ),

        // UseCase層（ビジネスロジック）
        .target(
            name: "UseCase",
            dependencies: ["Domain"]
        ),
        .testTarget(
            name: "UseCaseTests",
            dependencies: ["UseCase"]
        ),

        // Infrastructure層（リポジトリ実装、DB、イベント記録）
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift")
            ]
        ),
        .testTarget(
            name: "InfrastructureTests",
            dependencies: ["Infrastructure"]
        ),

        // MCPサーバー
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "MCPServerTests",
            dependencies: ["MCPServer"]
        ),

        // SwiftUI Mac App
        .executableTarget(
            name: "App",
            dependencies: [
                "Domain",
                "UseCase",
                "Infrastructure"
            ]
        ),
        .testTarget(
            name: "AppTests",
            dependencies: [
                "App",
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "ViewInspector", package: "ViewInspector")
            ]
        )
    ]
)
