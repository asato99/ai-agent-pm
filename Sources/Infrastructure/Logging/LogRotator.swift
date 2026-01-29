// Sources/Infrastructure/Logging/LogRotator.swift
// ログローテーション機能

import Foundation

/// ログファイルのローテーション（古いファイルの削除）を管理
///
/// 指定された保持期間を超えたログファイルを自動的に削除する。
/// デーモン起動時やアプリ起動時に呼び出すことを想定。
public final class LogRotator: @unchecked Sendable {

    /// デフォルトの保持日数
    public static let defaultRetentionDays = 7

    /// デフォルトのファイルパターン
    public static let defaultFilePattern = "*.log"

    private let directory: String
    private let retentionDays: Int
    private let filePattern: String
    private let fileManager: FileManager

    /// 初期化
    ///
    /// - Parameters:
    ///   - directory: ログファイルが格納されているディレクトリパス
    ///   - retentionDays: 保持日数（この日数を超えたファイルを削除）
    ///   - filePattern: 削除対象のファイルパターン（デフォルト: "*.log"）
    ///   - fileManager: FileManager（テスト用にDI可能）
    public init(
        directory: String,
        retentionDays: Int = defaultRetentionDays,
        filePattern: String = defaultFilePattern,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.filePattern = filePattern
        self.fileManager = fileManager
    }

    /// ローテーションを実行
    ///
    /// 保持期間を超えたログファイルを削除する。
    ///
    /// - Returns: 削除されたファイル数
    @discardableResult
    public func rotate() -> Int {
        guard fileManager.fileExists(atPath: directory) else {
            return 0
        }

        guard let files = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return 0
        }

        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        var deletedCount = 0

        for fileName in files {
            guard matchesPattern(fileName) else {
                continue
            }

            let filePath = (directory as NSString).appendingPathComponent(fileName)

            guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }

            // 保持期間を超えたファイルを削除
            if modificationDate < cutoffDate {
                do {
                    try fileManager.removeItem(atPath: filePath)
                    deletedCount += 1
                } catch {
                    // 削除に失敗しても続行
                    continue
                }
            }
        }

        return deletedCount
    }

    /// ファイル名がパターンにマッチするかチェック
    private func matchesPattern(_ fileName: String) -> Bool {
        // シンプルなワイルドカードマッチング
        // "*.log" -> ".log"で終わるファイル
        if filePattern.hasPrefix("*") {
            let suffix = String(filePattern.dropFirst())
            return fileName.hasSuffix(suffix)
        }

        // 完全一致
        return fileName == filePattern
    }
}

// MARK: - LogMigrator

/// 既存のログファイルを日付付きファイルに移行
///
/// `mcp-server.log` → `mcp-server-2026-01-29.log` のように移行する。
/// 既存ファイルが存在する場合のみ移行を実行する。
public final class LogMigrator: @unchecked Sendable {

    private let directory: String
    private let fileManager: FileManager
    private let dateFormatter: DateFormatter

    /// 初期化
    ///
    /// - Parameters:
    ///   - directory: ログディレクトリパス
    ///   - fileManager: FileManager（テスト用にDI可能）
    public init(directory: String, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
    }

    /// 既存のログファイルを日付付きファイルに移行
    ///
    /// 例: `mcp-server.log` → `mcp-server-2026-01-29.log`
    ///
    /// - Parameter prefix: ファイル名のプレフィックス（例: "mcp-server"）
    /// - Returns: 移行が実行されたかどうか
    @discardableResult
    public func migrateIfNeeded(prefix: String) -> Bool {
        let oldFileName = "\(prefix).log"
        let oldFilePath = (directory as NSString).appendingPathComponent(oldFileName)

        // 既存ファイルが存在しない場合は何もしない
        guard fileManager.fileExists(atPath: oldFilePath) else {
            return false
        }

        // ファイルの更新日時を取得
        guard let attributes = try? fileManager.attributesOfItem(atPath: oldFilePath),
              let modificationDate = attributes[.modificationDate] as? Date else {
            return false
        }

        // 新しいファイル名を生成（ファイルの更新日を使用）
        let dateString = dateFormatter.string(from: modificationDate)
        let newFileName = "\(prefix)-\(dateString).log"
        let newFilePath = (directory as NSString).appendingPathComponent(newFileName)

        do {
            if fileManager.fileExists(atPath: newFilePath) {
                // 新しいファイルが既に存在する場合は追記
                let oldContent = try Data(contentsOf: URL(fileURLWithPath: oldFilePath))
                let fileHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: newFilePath))
                fileHandle.seekToEndOfFile()
                fileHandle.write(oldContent)
                try fileHandle.close()
                try fileManager.removeItem(atPath: oldFilePath)
            } else {
                // 新しいファイルが存在しない場合はリネーム
                try fileManager.moveItem(atPath: oldFilePath, toPath: newFilePath)
            }
            return true
        } catch {
            // 移行に失敗しても続行
            return false
        }
    }
}

// MARK: - LogRotationConfig

/// ログローテーションの設定
public struct LogRotationConfig: Sendable {

    /// 保持日数
    public let retentionDays: Int

    /// ファイルパターン
    public let filePattern: String

    /// デフォルト設定
    public static let `default` = LogRotationConfig(
        retentionDays: LogRotator.defaultRetentionDays,
        filePattern: LogRotator.defaultFilePattern
    )

    /// 初期化
    public init(retentionDays: Int, filePattern: String = LogRotator.defaultFilePattern) {
        self.retentionDays = retentionDays
        self.filePattern = filePattern
    }

    /// 環境変数から設定を読み込む
    ///
    /// - `MCP_LOG_RETENTION_DAYS`: 保持日数（デフォルト: 7）
    public static func fromEnvironment() -> LogRotationConfig {
        let retentionDays: Int
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_RETENTION_DAYS"],
           let days = Int(envValue), days > 0 {
            retentionDays = days
        } else {
            retentionDays = LogRotator.defaultRetentionDays
        }

        return LogRotationConfig(retentionDays: retentionDays)
    }
}
