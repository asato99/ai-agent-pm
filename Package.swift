// swift-tools-version: 5.9
// Package.swift
// SPM ビルド定義（Linux/WSL2 対応）
//
// macOS: Xcode (project.yml) または SPM どちらでもビルド可能
// Linux: SPM のみ（MCPServer, RESTServer のサーバーコンポーネント）
//
// 使用方法:
//   swift build -c release --product mcp-server-pm
//   swift build -c release --product rest-server-pm

import PackageDescription

let package = Package(
    name: "AIAgentPM",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mcp-server-pm", targets: ["MCPServer"]),
        .executable(name: "rest-server-pm", targets: ["RESTServer"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "6.29.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/hummingbird-project/hummingbird.git", from: "2.0.0"),
    ],
    targets: [
        // Domain層（エンティティ、値オブジェクト、リポジトリプロトコル）
        .target(
            name: "Domain",
            path: "Sources/Domain"
        ),

        // UseCase層（ビジネスロジック）
        .target(
            name: "UseCase",
            dependencies: ["Domain"],
            path: "Sources/UseCase"
        ),

        // Infrastructure層（DB・リポジトリ実装）
        .target(
            name: "Infrastructure",
            dependencies: [
                "Domain",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            path: "Sources/Infrastructure"
        ),

        // MCPServer共有ライブラリ（RESTServerから参照される共通コード）
        .target(
            name: "MCPServerLib",
            dependencies: [
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MCPServer",
            exclude: ["App.swift"]
        ),

        // MCPサーバー実行ファイル
        .executableTarget(
            name: "MCPServer",
            dependencies: [
                "MCPServerLib",
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/MCPServerEntry"
        ),

        // RESTサーバー実行ファイル
        .executableTarget(
            name: "RESTServer",
            dependencies: [
                "MCPServerLib",
                "Domain",
                "UseCase",
                "Infrastructure",
                .product(name: "Hummingbird", package: "hummingbird"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/RESTServer"
        ),
    ]
)
