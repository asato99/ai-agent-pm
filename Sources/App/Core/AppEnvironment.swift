// Sources/App/Core/AppEnvironment.swift
// アプリケーション環境設定の集約

import Foundation
import Infrastructure

/// アプリケーション実行環境の設定
/// UIテストモードの検出、データベースパス設定などを集約
public enum AppEnvironment {

    // MARK: - UITest Detection

    /// UIテストモードかどうか（-UITesting引数で判定）
    /// 本番ビルドでも参照可能（false固定となる場合がある）
    public static var isUITesting: Bool {
        CommandLine.arguments.contains("-UITesting")
    }

    // MARK: - Database Paths

    /// UIテスト用データベースパス
    /// テストスクリプトと同じパスを使用（/tmp/AIAgentPM_UITest.db）
    public static let uiTestDatabasePath = "/tmp/AIAgentPM_UITest.db"

    /// 現在の環境に応じたデータベースパスを取得
    public static var databasePath: String {
        if isUITesting {
            return uiTestDatabasePath
        }
        return AppConfig.databasePath
    }

    // MARK: - Database Cleanup

    /// UIテスト用データベースをクリーンアップ
    /// テスト開始前にDB及びジャーナルファイルを削除
    public static func cleanupTestDatabase() {
        let paths = [
            uiTestDatabasePath,
            uiTestDatabasePath + "-shm",
            uiTestDatabasePath + "-wal"
        ]
        for path in paths {
            try? FileManager.default.removeItem(atPath: path)
        }
    }
}

// MARK: - DEBUG専用機能

#if DEBUG

extension AppEnvironment {

    /// テストシナリオ（-UITestScenario:XXX で指定）
    /// DEBUG ビルドでのみ利用可能
    public static var testScenario: TestScenario {
        for arg in CommandLine.arguments {
            if arg.hasPrefix("-UITestScenario:") {
                let scenario = String(arg.dropFirst("-UITestScenario:".count))
                return TestScenario(rawValue: scenario) ?? .basic
            }
        }
        return .basic
    }

    // MARK: - Debug Logging Paths

    /// UIテストデバッグログファイルパス
    public static let debugLogPath = "/tmp/aiagentpm_debug.log"

    /// UIテスト用ワークフローデバッグファイルパス
    public static let workflowDebugPath = "/tmp/uitest_workflow_debug.txt"

    /// UIテスト用シナリオデバッグファイルパス
    public static let scenarioDebugPath = "/tmp/uitest_scenario_debug.txt"

    // MARK: - Environment Variables for Testing

    /// 環境変数キー定義
    public enum EnvKeys {
        /// UC001用作業ディレクトリ
        public static let uc001WorkingDir = "UC001_WORKING_DIR"
        /// UC001用出力ファイル
        public static let uc001OutputFile = "UC001_OUTPUT_FILE"
    }

    /// UC001用作業ディレクトリ（環境変数またはデフォルト）
    public static var uc001WorkingDir: String {
        ProcessInfo.processInfo.environment[EnvKeys.uc001WorkingDir] ?? "/tmp/uc001_test"
    }

    /// UC001用出力ファイル名（環境変数またはデフォルト）
    public static var uc001OutputFile: String {
        ProcessInfo.processInfo.environment[EnvKeys.uc001OutputFile] ?? "test_output.md"
    }
}

// MARK: - Debug Logging Functions

/// UIテスト用デバッグログ出力
/// XCUITest環境ではNSLog/printがキャプチャされないため、ファイルに出力
public func appDebugLog(_ message: String) {
    let timestamp = ISO8601DateFormatter().string(from: Date())
    let logMessage = "[\(timestamp)] [AppDelegate] \(message)\n"
    NSLog("[AppDelegate] %@", message)

    let logFile = AppEnvironment.debugLogPath
    if let data = logMessage.data(using: .utf8) {
        if FileManager.default.fileExists(atPath: logFile) {
            if let handle = FileHandle(forWritingAtPath: logFile) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            }
        } else {
            FileManager.default.createFile(atPath: logFile, contents: data, attributes: nil)
        }
    }
}

// MARK: - Debug File Extensions

extension String {
    /// デバッグ用：ファイルに追記
    /// DEBUG ビルドでのみ利用可能
    func appendToFile(_ path: String) throws {
        if let handle = FileHandle(forWritingAtPath: path) {
            defer { handle.closeFile() }
            handle.seekToEndOfFile()
            if let data = (self + "\n").data(using: .utf8) {
                handle.write(data)
            }
        } else {
            try self.write(toFile: path, atomically: true, encoding: .utf8)
        }
    }
}

#endif
