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
        lock.unlock()

        // レベルフィルタリング
        guard level >= currentMin else { return }

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
