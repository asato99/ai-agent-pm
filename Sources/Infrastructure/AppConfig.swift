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

    /// アプリケーションデータ格納ディレクトリ
    /// macOS: ~/Library/Application Support/AIAgentPM/
    /// Linux: $XDG_DATA_HOME/AIAgentPM/ or ~/.local/share/AIAgentPM/
    public static var appSupportDirectory: URL {
        #if os(Linux)
        let baseDir = ProcessInfo.processInfo.environment["XDG_DATA_HOME"]
            ?? "\(NSHomeDirectory())/.local/share"
        return URL(fileURLWithPath: baseDir).appendingPathComponent(appName)
        #else
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent(appName)
        #endif
    }

    /// データベースファイル名
    public static let databaseFileName = "pm.db"

    /// デフォルトのデータベースパス
    /// macOS: ~/Library/Application Support/AIAgentPM/pm.db
    /// Linux: ~/.local/share/AIAgentPM/pm.db
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

    /// Web Server設定
    public enum WebServer {
        /// ポート設定用の環境変数名
        public static let portEnvKey = "AIAGENTPM_WEBSERVER_PORT"

        /// ポート設定用のUserDefaultsキー（macOSのみ使用）
        public static let portUserDefaultsKey = "webServerPort"

        /// デフォルトのポート番号
        public static let defaultPort = 8080

        /// 実際に使用するポート番号
        /// 優先順位: 環境変数 > UserDefaults(macOSのみ) > デフォルト値
        public static var port: Int {
            // 1. 環境変数を優先
            if let envPort = ProcessInfo.processInfo.environment[portEnvKey],
               let port = Int(envPort), isValidPort(port) {
                return port
            }

            #if !os(Linux)
            // 2. UserDefaultsを確認（macOSのみ）
            let userDefaultsPort = UserDefaults.standard.integer(forKey: portUserDefaultsKey)
            if userDefaultsPort != 0 && isValidPort(userDefaultsPort) {
                return userDefaultsPort
            }
            #endif

            // 3. デフォルト値
            return defaultPort
        }

        /// ポートをUserDefaultsに保存し、web-ui用の設定ファイルも更新
        public static func setPort(_ port: Int) {
            guard isValidPort(port) else { return }
            #if !os(Linux)
            UserDefaults.standard.set(port, forKey: portUserDefaultsKey)
            #endif
            writePortConfigFile(port)
        }

        /// ポートをデフォルトにリセット
        public static func resetPort() {
            #if !os(Linux)
            UserDefaults.standard.removeObject(forKey: portUserDefaultsKey)
            #endif
            writePortConfigFile(defaultPort)
        }

        /// 有効なポート番号か確認
        public static func isValidPort(_ port: Int) -> Bool {
            return port >= 1024 && port <= 65535
        }

        /// web-ui開発用のポート設定ファイルを書き出す
        /// macOS: ~/Library/Application Support/AIAgentPM/webserver-port
        /// Linux: ~/.local/share/AIAgentPM/webserver-port
        private static func writePortConfigFile(_ port: Int) {
            let dir = appSupportDirectory

            // ディレクトリがなければ作成
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let portFile = dir.appendingPathComponent("webserver-port")
            try? String(port).write(to: portFile, atomically: true, encoding: .utf8)
        }
    }
}
