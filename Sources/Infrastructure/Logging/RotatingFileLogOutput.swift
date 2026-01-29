// Sources/Infrastructure/Logging/RotatingFileLogOutput.swift
// 日付別ログファイル出力

import Foundation

/// 日付別にファイルを分割するログ出力
///
/// ログエントリのタイムスタンプに基づいて、日付ごとに別ファイルへ出力する。
/// ファイル名の形式: `{prefix}-{yyyy-MM-dd}.log`
///
/// 例: `mcp-server-2026-01-29.log`
public final class RotatingFileLogOutput: LogOutput, @unchecked Sendable {

    /// ファイル出力は常に全レベルを記録（フィルタなし）
    public let minimumLevel: LogLevel? = nil

    private let directory: String
    private let prefix: String
    private let format: LogFormat
    private let lock = NSLock()
    private var fileHandles: [String: FileHandle] = [:]
    private let dateFormatter: DateFormatter

    /// 初期化
    ///
    /// - Parameters:
    ///   - directory: ログファイルを出力するディレクトリパス
    ///   - prefix: ファイル名のプレフィックス（例: "mcp-server"）
    ///   - format: 出力フォーマット（デフォルト: .text）
    public init(directory: String, prefix: String, format: LogFormat = .text) {
        self.directory = directory
        self.prefix = prefix
        self.format = format
        self.dateFormatter = DateFormatter()
        self.dateFormatter.dateFormat = "yyyy-MM-dd"
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

        // ファイルハンドルを取得または作成
        let handle = getOrCreateHandle(for: filePath, dateKey: dateString)

        if let data = (line + "\n").data(using: .utf8) {
            handle.write(data)
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
