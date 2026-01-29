// Sources/Infrastructure/Logging/MCPLogger.swift
// MCPログシステムのメインLoggerクラス

import Foundation

// MARK: - LoggerProtocol

/// Loggerのプロトコル（テスト用DI）
public protocol LoggerProtocol: Sendable {
    func log(
        _ level: LogLevel,
        category: LogCategory,
        message: String,
        operation: String?,
        agentId: String?,
        projectId: String?,
        details: [String: Any]?
    )

    func setMinimumLevel(_ level: LogLevel)
}

// MARK: - MCPLogger

/// MCPログシステムのメインLoggerクラス
///
/// 複数の出力先への同時出力、レベルフィルタリング、
/// コンテキスト情報の付与などをサポートする。
public final class MCPLogger: LoggerProtocol, @unchecked Sendable {
    /// シングルトンインスタンス
    public static let shared = MCPLogger()

    private let lock = NSLock()
    private var outputs: [LogOutput] = []
    private var minimumLevel: LogLevel = .info
    private var categoryLevels: [LogCategory: LogLevel] = [:]

    // MARK: - Initialization

    public init() {}

    // MARK: - Configuration

    /// 最小ログレベルを設定
    ///
    /// 設定したレベル未満のログは出力されない。
    ///
    /// - Parameter level: 最小ログレベル
    public func setMinimumLevel(_ level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        minimumLevel = level
    }

    /// 現在の最小ログレベルを取得
    public var currentMinimumLevel: LogLevel {
        lock.lock()
        defer { lock.unlock() }
        return minimumLevel
    }

    /// カテゴリ別の最小ログレベルを設定
    ///
    /// 特定カテゴリのログレベルを個別に設定する。
    /// グローバルレベルより優先される。
    ///
    /// - Parameters:
    ///   - category: 対象カテゴリ
    ///   - level: 最小ログレベル
    public func setCategoryLevel(_ category: LogCategory, level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        categoryLevels[category] = level
    }

    /// カテゴリ別の最小ログレベルを削除
    ///
    /// 個別設定を削除し、グローバルレベルに戻す。
    ///
    /// - Parameter category: 対象カテゴリ
    public func clearCategoryLevel(_ category: LogCategory) {
        lock.lock()
        defer { lock.unlock() }
        categoryLevels.removeValue(forKey: category)
    }

    /// 出力先を追加
    ///
    /// - Parameter output: 追加する出力先
    public func addOutput(_ output: LogOutput) {
        lock.lock()
        defer { lock.unlock() }
        outputs.append(output)
    }

    /// 出力先を削除
    ///
    /// - Parameter output: 削除する出力先
    public func removeOutput(_ output: LogOutput) {
        lock.lock()
        defer { lock.unlock() }
        outputs.removeAll { $0 === output }
    }

    /// 全ての出力先を削除
    public func removeAllOutputs() {
        lock.lock()
        defer { lock.unlock() }
        outputs.removeAll()
    }

    // MARK: - Logging Methods

    /// ログを出力
    ///
    /// - Parameters:
    ///   - level: ログレベル
    ///   - category: ログカテゴリ
    ///   - message: ログメッセージ
    ///   - operation: 操作名（オプション）
    ///   - agentId: エージェントID（オプション）
    ///   - projectId: プロジェクトID（オプション）
    ///   - details: 追加詳細情報（オプション）
    public func log(
        _ level: LogLevel,
        category: LogCategory,
        message: String,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        lock.lock()
        let currentMin = minimumLevel
        let currentOutputs = outputs
        let currentCategoryLevels = categoryLevels
        lock.unlock()

        // レベルフィルタリング（カテゴリ別設定を優先）
        let effectiveMinLevel = currentCategoryLevels[category] ?? currentMin
        guard level >= effectiveMinLevel else { return }

        let entry = LogEntry(
            timestamp: Date(),
            level: level,
            category: category,
            message: message,
            operation: operation,
            agentId: agentId,
            projectId: projectId,
            details: details
        )

        for output in currentOutputs {
            output.write(entry)
        }
    }

    // MARK: - Convenience Methods

    /// TRACEレベルのログを出力
    public func trace(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        log(.trace, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: details)
    }

    /// DEBUGレベルのログを出力
    public func debug(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        log(.debug, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: details)
    }

    /// INFOレベルのログを出力
    public func info(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        log(.info, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: details)
    }

    /// WARNレベルのログを出力
    public func warn(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        log(.warn, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: details)
    }

    /// ERRORレベルのログを出力
    public func error(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil,
        details: [String: Any]? = nil
    ) {
        log(.error, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: details)
    }
}

// MARK: - LogConfig

/// ログ設定
///
/// 環境変数からログレベルやフォーマットを読み取る。
public struct LogConfig: Sendable {

    /// ログレベル
    public let level: LogLevel

    /// 出力フォーマット
    public let format: LogFormat

    /// デフォルト設定
    public static let `default` = LogConfig(level: .info, format: .json)

    /// 初期化
    public init(level: LogLevel, format: LogFormat) {
        self.level = level
        self.format = format
    }

    /// 環境変数から設定を読み込む
    ///
    /// - `MCP_LOG_LEVEL`: ログレベル（TRACE, DEBUG, INFO, WARN, ERROR）
    /// - `MCP_LOG_FORMAT`: 出力フォーマット（json, text）
    public static func fromEnvironment() -> LogConfig {
        // ログレベル
        let level: LogLevel
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_LEVEL"],
           let parsedLevel = LogLevel(rawString: envValue) {
            level = parsedLevel
        } else {
            level = .info
        }

        // 出力フォーマット
        let format: LogFormat
        if let envValue = ProcessInfo.processInfo.environment["MCP_LOG_FORMAT"]?.lowercased() {
            switch envValue {
            case "json":
                format = .json
            case "text":
                format = .text
            default:
                format = .json
            }
        } else {
            format = .json
        }

        return LogConfig(level: level, format: format)
    }
}
