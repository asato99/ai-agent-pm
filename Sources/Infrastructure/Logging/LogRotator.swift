// Sources/Infrastructure/Logging/LogRotator.swift
// ログローテーション機能

import Foundation

/// ログファイルのローテーション（古いファイルの削除）を管理
///
/// 以下の条件でログファイルを削除する：
/// 1. 保持期間を超えたファイル（年齢ベース）
/// 2. 全体サイズが上限を超えた場合、古いファイルから削除（サイズベース）
///
/// デーモン起動時やアプリ起動時に呼び出すことを想定。
public final class LogRotator: @unchecked Sendable {

    /// デフォルトの保持日数
    public static let defaultRetentionDays = 7

    /// デフォルトのファイルパターン
    public static let defaultFilePattern = "*.log"

    /// デフォルトの最大全体サイズ（500MB）
    public static let defaultMaxTotalSize: UInt64 = 500 * 1024 * 1024

    private let directory: String
    private let retentionDays: Int
    private let filePattern: String
    private let maxTotalSize: UInt64
    private let fileManager: FileManager

    /// 初期化
    ///
    /// - Parameters:
    ///   - directory: ログファイルが格納されているディレクトリパス
    ///   - retentionDays: 保持日数（この日数を超えたファイルを削除）
    ///   - filePattern: 削除対象のファイルパターン（デフォルト: "*.log"）
    ///   - maxTotalSize: 最大全体サイズ（バイト）。超過時は古いファイルから削除。0で無制限
    ///   - fileManager: FileManager（テスト用にDI可能）
    public init(
        directory: String,
        retentionDays: Int = defaultRetentionDays,
        filePattern: String = defaultFilePattern,
        maxTotalSize: UInt64 = defaultMaxTotalSize,
        fileManager: FileManager = .default
    ) {
        self.directory = directory
        self.retentionDays = retentionDays
        self.filePattern = filePattern
        self.maxTotalSize = maxTotalSize
        self.fileManager = fileManager
    }

    /// ローテーションを実行
    ///
    /// 1. 保持期間を超えたログファイルを削除
    /// 2. 全体サイズが上限を超えている場合、古いファイルから削除
    ///
    /// - Returns: 削除されたファイル数
    @discardableResult
    public func rotate() -> Int {
        var deletedCount = 0

        // 1. 年齢ベースの削除
        deletedCount += rotateByAge()

        // 2. サイズベースの削除
        if maxTotalSize > 0 {
            deletedCount += rotateByTotalSize()
        }

        return deletedCount
    }

    /// 年齢ベースのローテーション
    ///
    /// 保持期間を超えたログファイルを削除する。
    ///
    /// - Returns: 削除されたファイル数
    @discardableResult
    public func rotateByAge() -> Int {
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

    /// サイズベースのローテーション
    ///
    /// 全体サイズが上限を超えている場合、古いファイルから削除する。
    ///
    /// - Returns: 削除されたファイル数
    @discardableResult
    public func rotateByTotalSize() -> Int {
        guard maxTotalSize > 0 else {
            return 0
        }

        let filesWithInfo = getMatchingFilesWithInfo()
        let currentTotalSize = filesWithInfo.reduce(0) { $0 + $1.size }

        guard currentTotalSize > maxTotalSize else {
            return 0
        }

        // 古いファイルから順にソート（更新日時の昇順）
        let sortedFiles = filesWithInfo.sorted { $0.modificationDate < $1.modificationDate }

        var deletedCount = 0
        var remainingSize = currentTotalSize

        for fileInfo in sortedFiles {
            // 上限以下になったら終了
            guard remainingSize > maxTotalSize else {
                break
            }

            do {
                try fileManager.removeItem(atPath: fileInfo.path)
                remainingSize -= fileInfo.size
                deletedCount += 1
            } catch {
                // 削除に失敗しても続行
                continue
            }
        }

        return deletedCount
    }

    /// 全体サイズを取得
    ///
    /// - Returns: マッチするファイルの合計サイズ（バイト）
    public func getTotalSize() -> UInt64 {
        getMatchingFilesWithInfo().reduce(0) { $0 + $1.size }
    }

    /// マッチするファイルの情報を取得
    private func getMatchingFilesWithInfo() -> [FileInfo] {
        guard fileManager.fileExists(atPath: directory),
              let files = try? fileManager.contentsOfDirectory(atPath: directory) else {
            return []
        }

        var result: [FileInfo] = []

        for fileName in files {
            guard matchesPattern(fileName) else {
                continue
            }

            let filePath = (directory as NSString).appendingPathComponent(fileName)

            guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
                  let size = attributes[.size] as? UInt64,
                  let modificationDate = attributes[.modificationDate] as? Date else {
                continue
            }

            result.append(FileInfo(
                path: filePath,
                fileName: fileName,
                size: size,
                modificationDate: modificationDate
            ))
        }

        return result
    }

    /// ファイル情報
    private struct FileInfo {
        let path: String
        let fileName: String
        let size: UInt64
        let modificationDate: Date
    }

    /// ファイル名がパターンにマッチするかチェック
    private func matchesPattern(_ fileName: String) -> Bool {
        // シンプルなワイルドカードマッチング
        // "*.log" -> ".log"で終わるファイル、または ".log.N" で終わるファイル
        if filePattern.hasPrefix("*") {
            let suffix = String(filePattern.dropFirst())
            // 基本パターン（例: ".log"）にマッチ
            if fileName.hasSuffix(suffix) {
                return true
            }
            // ローテーションファイル（例: ".log.1", ".log.2"）にもマッチ
            // パターン: suffix + "." + 数字
            let rotatedPattern = suffix + "."
            if let range = fileName.range(of: rotatedPattern),
               range.upperBound < fileName.endIndex {
                let afterSuffix = String(fileName[range.upperBound...])
                return afterSuffix.allSatisfy { $0.isNumber }
            }
            return false
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

// MARK: - SizeBasedLogRotator

/// サイズベースのログローテーション
///
/// ファイルサイズが上限を超えた場合に番号付きファイルにローテーションする。
/// 例: `mcp-server-2026-01-30.log` → `mcp-server-2026-01-30.log.1`
///
/// ログを欠損させずに保持するため、古いファイルは番号を付けて保存する。
public final class SizeBasedLogRotator: @unchecked Sendable {

    /// デフォルトの最大ファイルサイズ（50MB）
    public static let defaultMaxFileSize: UInt64 = 50 * 1024 * 1024

    /// デフォルトの最大ローテーション数
    public static let defaultMaxRotations: Int = 10

    private let maxFileSize: UInt64
    private let maxRotations: Int
    private let fileManager: FileManager

    /// 初期化
    ///
    /// - Parameters:
    ///   - maxFileSize: 最大ファイルサイズ（バイト）。超過するとローテーション
    ///   - maxRotations: 最大ローテーション数。超えた古いファイルは削除
    ///   - fileManager: FileManager（テスト用にDI可能）
    public init(
        maxFileSize: UInt64 = defaultMaxFileSize,
        maxRotations: Int = defaultMaxRotations,
        fileManager: FileManager = .default
    ) {
        self.maxFileSize = maxFileSize
        self.maxRotations = maxRotations
        self.fileManager = fileManager
    }

    /// ファイルサイズをチェックし、必要に応じてローテーション
    ///
    /// - Parameter filePath: チェック対象のログファイルパス
    /// - Returns: ローテーションが実行されたかどうか
    @discardableResult
    public func rotateIfNeeded(filePath: String) -> Bool {
        guard fileManager.fileExists(atPath: filePath) else {
            return false
        }

        guard let attributes = try? fileManager.attributesOfItem(atPath: filePath),
              let fileSize = attributes[.size] as? UInt64 else {
            return false
        }

        // サイズ上限未満なら何もしない
        guard fileSize >= maxFileSize else {
            return false
        }

        return rotate(filePath: filePath)
    }

    /// ローテーションを実行
    ///
    /// 1. 既存の番号付きファイルをシフト (.1 → .2, .2 → .3, ...)
    /// 2. 現在のファイルを .1 にリネーム
    /// 3. 最大数を超えた古いファイルを削除
    ///
    /// - Parameter filePath: ローテーション対象のファイルパス
    /// - Returns: 成功したかどうか
    private func rotate(filePath: String) -> Bool {
        // 最大数を超えたファイルを削除
        let maxPath = "\(filePath).\(maxRotations)"
        if fileManager.fileExists(atPath: maxPath) {
            try? fileManager.removeItem(atPath: maxPath)
        }

        // 既存の番号付きファイルをシフト（大きい番号から順に）
        for i in stride(from: maxRotations - 1, through: 1, by: -1) {
            let currentPath = "\(filePath).\(i)"
            let nextPath = "\(filePath).\(i + 1)"

            if fileManager.fileExists(atPath: currentPath) {
                try? fileManager.moveItem(atPath: currentPath, toPath: nextPath)
            }
        }

        // 現在のファイルを .1 にリネーム
        let firstRotatedPath = "\(filePath).1"
        do {
            try fileManager.moveItem(atPath: filePath, toPath: firstRotatedPath)
            return true
        } catch {
            return false
        }
    }

    /// 指定パスの全ローテーションファイルを取得
    ///
    /// - Parameter basePath: ベースとなるログファイルパス
    /// - Returns: ローテーションファイルのパス一覧（番号順）
    public func getRotatedFiles(basePath: String) -> [String] {
        var files: [String] = []
        for i in 1...maxRotations {
            let path = "\(basePath).\(i)"
            if fileManager.fileExists(atPath: path) {
                files.append(path)
            }
        }
        return files
    }

    /// ローテーションファイルを含む全ファイルの合計サイズを取得
    ///
    /// - Parameter basePath: ベースとなるログファイルパス
    /// - Returns: 合計サイズ（バイト）
    public func getTotalSize(basePath: String) -> UInt64 {
        var totalSize: UInt64 = 0

        // ベースファイル
        if let attrs = try? fileManager.attributesOfItem(atPath: basePath),
           let size = attrs[.size] as? UInt64 {
            totalSize += size
        }

        // ローテーションファイル
        for path in getRotatedFiles(basePath: basePath) {
            if let attrs = try? fileManager.attributesOfItem(atPath: path),
               let size = attrs[.size] as? UInt64 {
                totalSize += size
            }
        }

        return totalSize
    }
}

// MARK: - LogRotationConfig

/// ログローテーションの設定
public struct LogRotationConfig: Sendable {

    /// 保持日数
    public let retentionDays: Int

    /// ファイルパターン
    public let filePattern: String

    /// 最大ファイルサイズ（バイト）- 単一ファイルの上限
    public let maxFileSize: UInt64

    /// 最大ローテーション数
    public let maxRotations: Int

    /// 最大全体サイズ（バイト）- 全ログファイルの合計上限
    public let maxTotalSize: UInt64

    /// デフォルト設定
    public static let `default` = LogRotationConfig(
        retentionDays: LogRotator.defaultRetentionDays,
        filePattern: LogRotator.defaultFilePattern,
        maxFileSize: SizeBasedLogRotator.defaultMaxFileSize,
        maxRotations: SizeBasedLogRotator.defaultMaxRotations,
        maxTotalSize: LogRotator.defaultMaxTotalSize
    )

    /// 初期化
    public init(
        retentionDays: Int,
        filePattern: String = LogRotator.defaultFilePattern,
        maxFileSize: UInt64 = SizeBasedLogRotator.defaultMaxFileSize,
        maxRotations: Int = SizeBasedLogRotator.defaultMaxRotations,
        maxTotalSize: UInt64 = LogRotator.defaultMaxTotalSize
    ) {
        self.retentionDays = retentionDays
        self.filePattern = filePattern
        self.maxFileSize = maxFileSize
        self.maxRotations = maxRotations
        self.maxTotalSize = maxTotalSize
    }

    /// 環境変数から設定を読み込む
    ///
    /// - `MCP_LOG_RETENTION_DAYS`: 保持日数（デフォルト: 7）
    /// - `MCP_LOG_MAX_FILE_SIZE_MB`: 最大ファイルサイズMB（デフォルト: 50）
    /// - `MCP_LOG_MAX_ROTATIONS`: 最大ローテーション数（デフォルト: 10）
    /// - `MCP_LOG_MAX_TOTAL_SIZE_MB`: 最大全体サイズMB（デフォルト: 500）
    public static func fromEnvironment() -> LogRotationConfig {
        let retentionDays: Int
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_RETENTION_DAYS"],
           let days = Int(envValue), days > 0 {
            retentionDays = days
        } else {
            retentionDays = LogRotator.defaultRetentionDays
        }

        let maxFileSize: UInt64
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_MAX_FILE_SIZE_MB"],
           let mb = UInt64(envValue), mb > 0 {
            maxFileSize = mb * 1024 * 1024
        } else {
            maxFileSize = SizeBasedLogRotator.defaultMaxFileSize
        }

        let maxRotations: Int
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_MAX_ROTATIONS"],
           let rotations = Int(envValue), rotations > 0 {
            maxRotations = rotations
        } else {
            maxRotations = SizeBasedLogRotator.defaultMaxRotations
        }

        let maxTotalSize: UInt64
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_MAX_TOTAL_SIZE_MB"],
           let mb = UInt64(envValue), mb > 0 {
            maxTotalSize = mb * 1024 * 1024
        } else {
            maxTotalSize = LogRotator.defaultMaxTotalSize
        }

        return LogRotationConfig(
            retentionDays: retentionDays,
            maxFileSize: maxFileSize,
            maxRotations: maxRotations,
            maxTotalSize: maxTotalSize
        )
    }
}
