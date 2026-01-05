// Sources/Infrastructure/AppConfig.swift
// アプリケーション共通設定
// App と MCPServer の両方がこの設定を参照する

import Foundation

/// アプリケーション全体で共有される設定
/// AppとMCPServerは常にこの設定を通じてDBパスを取得することで一致を保証
public enum AppConfig {
    /// アプリケーション名
    public static let appName = "AIAgentPM"

    /// DBパス切り替え用の環境変数名
    public static let databasePathEnvKey = "AIAGENTPM_DB_PATH"

    /// ~/Library/Application Support/AIAgentPM/
    public static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent(appName)
    }

    /// データベースファイル名
    public static let databaseFileName = "pm.db"

    /// デフォルトのデータベースパス
    /// ~/Library/Application Support/AIAgentPM/pm.db
    public static var defaultDatabasePath: String {
        appSupportDirectory.appendingPathComponent(databaseFileName).path
    }

    /// 実際に使用するデータベースパス
    /// 環境変数 AIAGENTPM_DB_PATH が設定されていればそれを使用、なければデフォルト
    /// AppとMCPServerは常にこのプロパティを使用すること
    public static var databasePath: String {
        ProcessInfo.processInfo.environment[databasePathEnvKey] ?? defaultDatabasePath
    }

    /// デフォルトエージェント設定
    public enum DefaultAgent {
        public static let id = "agt_claude"
        public static let name = "Claude Code"
        public static let role = "AI Assistant"
    }

    /// デフォルトプロジェクト設定
    public enum DefaultProject {
        public static let id = "prj_default"
        public static let name = "Default Project"
    }
}
