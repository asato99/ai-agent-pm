// Sources/Infrastructure/Logging/MockLogger.swift
// テスト用のモックロガー

import Foundation

// MARK: - MockLogEntry

/// モックロガー用のログエントリ
public struct MockLogEntry: Sendable {
    public let timestamp: Date
    public let level: LogLevel
    public let category: LogCategory
    public let message: String
    public let operation: String?
    public let agentId: String?
    public let projectId: String?

    public init(
        timestamp: Date = Date(),
        level: LogLevel,
        category: LogCategory,
        message: String,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.message = message
        self.operation = operation
        self.agentId = agentId
        self.projectId = projectId
    }
}

// MARK: - MockLogger

/// テスト用のモックロガー
///
/// ログをメモリに保持し、テスト中に検証可能にする。
/// スレッドセーフな実装。
public final class MockLogger: LoggerProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _logs: [MockLogEntry] = []
    private var _minimumLevel: LogLevel = .trace

    public init() {}

    // MARK: - LoggerProtocol

    public func log(
        _ level: LogLevel,
        category: LogCategory,
        message: String,
        operation: String?,
        agentId: String?,
        projectId: String?,
        details: [String: Any]?
    ) {
        lock.lock()
        defer { lock.unlock() }

        guard level >= _minimumLevel else { return }

        let entry = MockLogEntry(
            level: level,
            category: category,
            message: message,
            operation: operation,
            agentId: agentId,
            projectId: projectId
        )
        _logs.append(entry)
    }

    public func setMinimumLevel(_ level: LogLevel) {
        lock.lock()
        defer { lock.unlock() }
        _minimumLevel = level
    }

    // MARK: - Convenience Methods

    public func trace(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        log(.trace, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: nil)
    }

    public func debug(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        log(.debug, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: nil)
    }

    public func info(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        log(.info, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: nil)
    }

    public func warn(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        log(.warn, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: nil)
    }

    public func error(
        _ message: String,
        category: LogCategory,
        operation: String? = nil,
        agentId: String? = nil,
        projectId: String? = nil
    ) {
        log(.error, category: category, message: message,
            operation: operation, agentId: agentId, projectId: projectId, details: nil)
    }

    // MARK: - Test Utilities

    /// 全てのログエントリを取得
    public var logs: [MockLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _logs
    }

    /// 特定のレベルのログをフィルタリング
    public func logs(level: LogLevel) -> [MockLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _logs.filter { $0.level == level }
    }

    /// 特定のカテゴリのログをフィルタリング
    public func logs(category: LogCategory) -> [MockLogEntry] {
        lock.lock()
        defer { lock.unlock() }
        return _logs.filter { $0.category == category }
    }

    /// 特定の文字列を含むログが存在するか確認
    public func hasLog(containing text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _logs.contains { $0.message.contains(text) }
    }

    /// 特定のレベルで特定の文字列を含むログが存在するか確認
    public func hasLog(level: LogLevel, containing text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _logs.contains { $0.level == level && $0.message.contains(text) }
    }

    /// 特定のカテゴリで特定の文字列を含むログが存在するか確認
    public func hasLog(category: LogCategory, containing text: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return _logs.contains { $0.category == category && $0.message.contains(text) }
    }

    /// 全てのログをクリア
    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        _logs.removeAll()
    }
}
