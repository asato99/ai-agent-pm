// Sources/Infrastructure/Logging/LogOutput.swift
// ログ出力先プロトコルと実装

import Foundation

// MARK: - LogOutput Protocol

/// ログ出力先のプロトコル
///
/// 異なる出力先（stderr、ファイル等）を抽象化する。
/// クラス型に制限（identityベースの比較をサポートするため）。
public protocol LogOutput: AnyObject, Sendable {
    /// ログエントリを出力する
    func write(_ entry: LogEntry)
}

// MARK: - Log Format

/// ログの出力フォーマット
public enum LogFormat: Sendable {
    /// JSON形式（構造化ログ）
    case json
    /// テキスト形式（人間可読）
    case text
}

// MARK: - StderrLogOutput

/// 標準エラー出力へのログ出力
///
/// コンソールやターミナルでのデバッグ用。
/// テキスト形式で出力する。
public final class StderrLogOutput: LogOutput, @unchecked Sendable {
    private let lock = NSLock()

    public init() {}

    public func write(_ entry: LogEntry) {
        let text = entry.toText()
        lock.lock()
        defer { lock.unlock() }
        fputs(text + "\n", stderr)
    }
}

// MARK: - FileLogOutput

/// ファイルへのログ出力
///
/// ログファイルへの永続化用。
/// JSON形式またはテキスト形式を選択可能。
public final class FileLogOutput: LogOutput, @unchecked Sendable {
    private let filePath: String
    private let format: LogFormat
    private let lock = NSLock()
    private var fileHandle: FileHandle?

    /// 初期化
    ///
    /// - Parameters:
    ///   - filePath: 出力先ファイルパス
    ///   - format: 出力フォーマット（デフォルト: .text）
    public init(filePath: String, format: LogFormat = .text) {
        self.filePath = filePath
        self.format = format
    }

    deinit {
        try? fileHandle?.close()
    }

    public func write(_ entry: LogEntry) {
        let line: String
        switch format {
        case .json:
            line = entry.toJSON()
        case .text:
            line = entry.toText()
        }

        lock.lock()
        defer { lock.unlock() }

        ensureFileExists()

        if let data = (line + "\n").data(using: .utf8) {
            if fileHandle == nil {
                fileHandle = FileHandle(forWritingAtPath: filePath)
                fileHandle?.seekToEndOfFile()
            }
            fileHandle?.write(data)
        }
    }

    private func ensureFileExists() {
        let fileManager = FileManager.default
        let directory = (filePath as NSString).deletingLastPathComponent

        // ディレクトリが存在しない場合は作成
        if !directory.isEmpty && !fileManager.fileExists(atPath: directory) {
            try? fileManager.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        // ファイルが存在しない場合は作成
        if !fileManager.fileExists(atPath: filePath) {
            fileManager.createFile(atPath: filePath, contents: nil)
        }
    }
}

// MARK: - CompositeLogOutput

/// 複数の出力先への同時出力
///
/// stderr + ファイルなど、複数の出力先に同時にログを書き込む。
public final class CompositeLogOutput: LogOutput, @unchecked Sendable {
    private let outputs: [LogOutput]

    /// 初期化
    ///
    /// - Parameter outputs: 出力先の配列
    public init(outputs: [LogOutput]) {
        self.outputs = outputs
    }

    public func write(_ entry: LogEntry) {
        for output in outputs {
            output.write(entry)
        }
    }
}
