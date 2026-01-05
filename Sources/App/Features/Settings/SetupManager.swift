// Sources/App/Features/Settings/SetupManager.swift
// Claude Code連携のセットアップ管理

import Foundation
import Domain
import Infrastructure

/// Claude Codeとの連携設定を管理
public final class SetupManager {

    // MARK: - Paths

    /// MCPサーバーの実行ファイルパス
    public var mcpServerPath: String {
        // アプリバンドル内のリソースから取得を試行
        if let bundlePath = Bundle.main.path(forResource: "mcp-server-pm", ofType: nil) {
            return bundlePath
        }

        // 開発時: 同じディレクトリから取得
        if let executableURL = Bundle.main.executableURL {
            let mcpPath = executableURL
                .deletingLastPathComponent()
                .appendingPathComponent("mcp-server-pm")
            if FileManager.default.fileExists(atPath: mcpPath.path) {
                return mcpPath.path
            }
        }

        // フォールバック: ビルドディレクトリから取得
        let buildPath = FileManager.default.currentDirectoryPath + "/.build/debug/mcp-server-pm"
        if FileManager.default.fileExists(atPath: buildPath) {
            return buildPath
        }

        return "/usr/local/bin/mcp-server-pm"
    }

    /// データベースパス（AppConfigから取得）
    public var databasePath: String {
        AppConfig.databasePath
    }

    /// Claude Code設定ファイルパス
    public var claudeConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".claude/claude_desktop_config.json").path
    }

    // MARK: - Config Generation

    /// Claude Code設定を生成（ステートレス設計: 引数なし）
    /// IDはキック時のプロンプトで提供され、各ツール呼び出し時に引数として渡される
    public func generateClaudeCodeConfig() -> String {
        let config: [String: Any] = [
            "mcpServers": [
                "agent-pm": [
                    "command": mcpServerPath,
                    "args": [] as [String]
                ]
            ]
        ]

        if let jsonData = try? JSONSerialization.data(withJSONObject: config, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }

        // フォールバック: 手動でJSON生成
        return """
        {
          "mcpServers": {
            "agent-pm": {
              "command": "\(mcpServerPath)",
              "args": []
            }
          }
        }
        """
    }

    // MARK: - Config Installation

    /// Claude Code設定をインストール
    public func installToClaudeCode() throws {
        let newConfig = generateClaudeCodeConfig()
        try installConfig(newConfig)
    }

    private func installConfig(_ newConfigJson: String) throws {
        let configPath = claudeConfigPath
        let configURL = URL(fileURLWithPath: configPath)
        let configDir = configURL.deletingLastPathComponent()

        // ディレクトリ作成
        try FileManager.default.createDirectory(
            at: configDir,
            withIntermediateDirectories: true
        )

        // 既存設定の読み込み
        var existingConfig: [String: Any] = [:]
        if FileManager.default.fileExists(atPath: configPath),
           let data = FileManager.default.contents(atPath: configPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            existingConfig = json
        }

        // 新しい設定をパース
        guard let newConfigData = newConfigJson.data(using: .utf8),
              let newConfig = try? JSONSerialization.jsonObject(with: newConfigData) as? [String: Any],
              let newServers = newConfig["mcpServers"] as? [String: Any] else {
            throw SetupError.invalidConfig
        }

        // 既存のmcpServersとマージ
        var mcpServers = existingConfig["mcpServers"] as? [String: Any] ?? [:]
        for (key, value) in newServers {
            mcpServers[key] = value
        }
        existingConfig["mcpServers"] = mcpServers

        // 書き込み
        let mergedData = try JSONSerialization.data(
            withJSONObject: existingConfig,
            options: [.prettyPrinted, .sortedKeys]
        )
        try mergedData.write(to: configURL)
    }

    // MARK: - Validation

    /// MCPサーバーが利用可能か確認
    public func validateMCPServer() -> ValidationResult {
        let path = mcpServerPath

        guard FileManager.default.fileExists(atPath: path) else {
            return .failure("MCP server not found at: \(path)")
        }

        guard FileManager.default.isExecutableFile(atPath: path) else {
            return .failure("MCP server is not executable: \(path)")
        }

        return .success
    }

    /// データベースが利用可能か確認
    public func validateDatabase() -> ValidationResult {
        let path = databasePath
        let directory = URL(fileURLWithPath: path).deletingLastPathComponent().path

        // ディレクトリが存在しない場合は作成可能か確認
        if !FileManager.default.fileExists(atPath: directory) {
            if FileManager.default.isWritableFile(atPath: URL(fileURLWithPath: directory).deletingLastPathComponent().path) {
                return .success
            } else {
                return .failure("Cannot create database directory: \(directory)")
            }
        }

        // ファイルが存在する場合は書き込み可能か確認
        if FileManager.default.fileExists(atPath: path) {
            if FileManager.default.isWritableFile(atPath: path) {
                return .success
            } else {
                return .failure("Database is not writable: \(path)")
            }
        }

        // ディレクトリへの書き込み権限確認
        if FileManager.default.isWritableFile(atPath: directory) {
            return .success
        } else {
            return .failure("Cannot write to database directory: \(directory)")
        }
    }

    /// Claude Code設定ディレクトリが利用可能か確認
    public func validateClaudeConfig() -> ValidationResult {
        let path = claudeConfigPath

        // ディレクトリが書き込み可能か確認
        let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
        if !FileManager.default.isWritableFile(atPath: homeDir) {
            return .failure("Cannot write to home directory")
        }

        // 既存設定があれば書き込み可能か確認
        if FileManager.default.fileExists(atPath: path) {
            if !FileManager.default.isWritableFile(atPath: path) {
                return .failure("Cannot modify existing config: \(path)")
            }
        }

        return .success
    }

    /// 全体の検証
    public func validateAll() -> [String: ValidationResult] {
        return [
            "mcpServer": validateMCPServer(),
            "database": validateDatabase(),
            "claudeConfig": validateClaudeConfig()
        ]
    }

    // MARK: - Types

    public enum ValidationResult: Equatable {
        case success
        case failure(String)

        public var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }

        public var message: String? {
            if case .failure(let msg) = self { return msg }
            return nil
        }
    }

    public enum SetupError: Error, LocalizedError {
        case invalidConfig
        case fileNotFound(String)
        case permissionDenied(String)
        case mergeError(String)

        public var errorDescription: String? {
            switch self {
            case .invalidConfig:
                return "Invalid configuration format"
            case .fileNotFound(let path):
                return "File not found: \(path)"
            case .permissionDenied(let path):
                return "Permission denied: \(path)"
            case .mergeError(let message):
                return "Failed to merge config: \(message)"
            }
        }
    }
}
