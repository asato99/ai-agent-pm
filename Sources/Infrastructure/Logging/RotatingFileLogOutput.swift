// Sources/Infrastructure/Logging/RotatingFileLogOutput.swift
// 日付別ログファイル出力（サイズベースローテーション対応）

import Foundation

/// 日付別にファイルを分割するログ出力
///
/// ログエントリのタイムスタンプに基づいて、日付ごとに別ファイルへ出力する。
/// さらに、ファイルサイズが上限を超えた場合は番号付きファイルにローテーションする。
///
/// ファイル名の形式: `{prefix}-{yyyy-MM-dd}.log`
/// ローテーション後: `{prefix}-{yyyy-MM-dd}.log.1`, `.2`, ...
///
/// 例: `mcp-server-2026-01-29.log`, `mcp-server-2026-01-29.log.1`
public final class RotatingFileLogOutput: LogOutput, @unchecked Sendable {

    /// ファイル出力は常に全レベルを記録（フィルタなし）
    public let minimumLevel: LogLevel? = nil

    private let directory: String
    private let prefix: String
    private let format: LogFormat
    private let lock = NSLock()
    private var fileHandles: [String: FileHandle] = [:]
    private let dateFormatter: DateFormatter
    private let sizeRotator: SizeBasedLogRotator
    private var writeCountSinceLastCheck: Int = 0
    private let checkInterval: Int = 100  // 100回書き込みごとにサイズチェック

    /// 初期化
    ///
    /// - Parameters:
    ///   - directory: ログファイルを出力するディレクトリパス
    ///   - prefix: ファイル名のプレフィックス（例: "mcp-server"）
    ///   - format: 出力フォーマット（デフォルト: .text）
    ///   - maxFileSize: 最大ファイルサイズ（デフォルト: 50MB）
    ///   - maxRotations: 最大ローテーション数（デフォルト: 10）
    public init(
        directory: String,
        prefix: String,
        format: LogFormat = .text,
        maxFileSize: UInt64 = SizeBasedLogRotator.defaultMaxFileSize,
        maxRotations: Int = SizeBasedLogRotator.defaultMaxRotations
    ) {
        self.directory = directory
        self.prefix = prefix
        self.format = format
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
        self.sizeRotator = SizeBasedLogRotator(
            maxFileSize: maxFileSize,
            maxRotations: maxRotations
        )
    }

    deinit {
        lock.lock()
        defer { lock.unlock() }
        for handle in fileHandles.values {
            try? handle.close()
        }
    }

    public func write(_ entry: LogEntry) {
        let line: String
        switch format {
        case .json:
            line = entry.toJSON()
        case .text:
            line = entry.toText()
        }

        let dateString = dateFormatter.string(from: entry.timestamp)
        let fileName = "\(prefix)-\(dateString).log"
        let filePath = (directory as NSString).appendingPathComponent(fileName)

        lock.lock()
        defer { lock.unlock() }

        ensureDirectoryExists()

        // 定期的にサイズベースローテーションをチェック
        writeCountSinceLastCheck += 1
        if writeCountSinceLastCheck >= checkInterval {
            writeCountSinceLastCheck = 0
            checkSizeBasedRotation(filePath: filePath, dateKey: dateString)
        }

        // ファイルハンドルを取得または作成
        let handle = getOrCreateHandle(for: filePath, dateKey: dateString)

        if let data = (line + "\n").data(using: .utf8) {
            handle.write(data)
        }
    }

    /// サイズベースローテーションのチェックと実行
    ///
    /// ファイルサイズが上限を超えている場合、ローテーションを実行し
    /// ファイルハンドルを再作成する。
    private func checkSizeBasedRotation(filePath: String, dateKey: String) {
        // 現在のハンドルを一旦閉じてファイルサイズを確定させる
        if let handle = fileHandles[dateKey] {
            try? handle.synchronize()
        }

        // サイズチェック＆ローテーション
        if sizeRotator.rotateIfNeeded(filePath: filePath) {
            // ローテーションが実行された場合、古いハンドルを閉じて削除
            if let oldHandle = fileHandles.removeValue(forKey: dateKey) {
                try? oldHandle.close()
            }
            // 次回のwrite時に新しいハンドルが作成される
        }
    }

    /// ディレクトリが存在することを確認
    private func ensureDirectoryExists() {
        let fileManager = FileManager.default
        if !fileManager.fileExists(atPath: directory) {
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }
    }

    /// ファイルハンドルを取得または作成
    private func getOrCreateHandle(for filePath: String, dateKey: String) -> FileHandle {
        if let existing = fileHandles[dateKey] {
            return existing
        }

        let fileManager = FileManager.default

        // ファイルが存在しない場合は作成
        if !fileManager.fileExists(atPath: filePath) {
            fileManager.createFile(atPath: filePath, contents: nil)
        }

        // ファイルハンドルを開く
        if let handle = FileHandle(forWritingAtPath: filePath) {
            handle.seekToEndOfFile()
            fileHandles[dateKey] = handle
            return handle
        }

        // フォールバック: 新しいファイルを作成して再試行
        fileManager.createFile(atPath: filePath, contents: nil)
        if let handle = FileHandle(forWritingAtPath: filePath) {
            fileHandles[dateKey] = handle
            return handle
        }

        // 最終フォールバック: stderrに出力
        return FileHandle.standardError
    }
}
