// Sources/Infrastructure/Logging/LogOutput.swift
// ログ出力先プロトコルと実装

import Foundation

// MARK: - LogOutput Protocol

/// ログ出力先のプロトコル
///
/// 異なる出力先（stderr、ファイル等）を抽象化する。
/// クラス型に制限（identityベースの比較をサポートするため）。
public protocol LogOutput: AnyObject, Sendable {
    /// この出力先の最小ログレベル（オプション）
    ///
    /// nilの場合は全てのログを出力する。
    /// 設定されている場合、このレベル未満のログは出力されない。
    var minimumLevel: LogLevel? { get }

    /// ログエントリを出力する
    func write(_ entry: LogEntry)

    /// このエントリを出力すべきかどうかを判定
    ///
    /// minimumLevelに基づいてフィルタリングする。
    func shouldWrite(_ entry: LogEntry) -> Bool
}

// MARK: - LogOutput Default Implementation

public extension LogOutput {
    /// デフォルト実装: minimumLevelがnilまたはエントリのレベルが最小レベル以上なら出力
    func shouldWrite(_ entry: LogEntry) -> Bool {
        guard let minLevel = minimumLevel else {
            return true  // フィルタなし
        }
        return entry.level >= minLevel
    }
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
    public let minimumLevel: LogLevel?
    private let lock = NSLock()

    /// 初期化
    ///
    /// - Parameter minimumLevel: 最小ログレベル（nilの場合は全レベル出力）
    public init(minimumLevel: LogLevel? = nil) {
        self.minimumLevel = minimumLevel
    }

    public func write(_ entry: LogEntry) {
        guard shouldWrite(entry) else { return }

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
/// デフォルトでは全レベルのログを記録する（minimumLevel = nil）。
public final class FileLogOutput: LogOutput, @unchecked Sendable {
    /// ファイル出力は常に全レベルを記録（フィルタなし）
    public let minimumLevel: LogLevel? = nil

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
/// 各出力先が独自のminimumLevelを持つため、CompositeLogOutput自体はフィルタしない。
public final class CompositeLogOutput: LogOutput, @unchecked Sendable {
    /// Compositeはフィルタしない（各出力先が個別にフィルタ）
    public let minimumLevel: LogLevel? = nil

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
