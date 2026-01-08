// Sources/Domain/Entities/ExecutionLog.swift
// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md - Phase 3-3 実行ログ

import Foundation

/// 実行ステータス
public enum ExecutionStatus: String, Codable, Sendable, CaseIterable {
    case running = "running"
    case completed = "completed"
    case failed = "failed"
}

/// タスク実行ログを表すエンティティ
/// 外部Runnerがタスクを実行した際の記録
public struct ExecutionLog: Identifiable, Equatable, Sendable {
    public let id: ExecutionLogID
    public let taskId: TaskID
    public let agentId: AgentID
    public private(set) var status: ExecutionStatus
    public let startedAt: Date
    public private(set) var completedAt: Date?
    public private(set) var exitCode: Int?
    public private(set) var durationSeconds: Double?
    public private(set) var logFilePath: String?
    public private(set) var errorMessage: String?

    /// 新しい実行ログを作成（実行開始時）
    public init(
        id: ExecutionLogID = .generate(),
        taskId: TaskID,
        agentId: AgentID,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.agentId = agentId
        self.status = .running
        self.startedAt = startedAt
        self.completedAt = nil
        self.exitCode = nil
        self.durationSeconds = nil
        self.logFilePath = nil
        self.errorMessage = nil
    }

    /// DBから復元用（全フィールド指定）
    public init(
        id: ExecutionLogID,
        taskId: TaskID,
        agentId: AgentID,
        status: ExecutionStatus,
        startedAt: Date,
        completedAt: Date?,
        exitCode: Int?,
        durationSeconds: Double?,
        logFilePath: String?,
        errorMessage: String?
    ) {
        self.id = id
        self.taskId = taskId
        self.agentId = agentId
        self.status = status
        self.startedAt = startedAt
        self.completedAt = completedAt
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.logFilePath = logFilePath
        self.errorMessage = errorMessage
    }

    /// 実行を完了としてマーク
    /// exitCode が 0 の場合は completed、それ以外は failed
    public mutating func complete(
        exitCode: Int,
        durationSeconds: Double,
        logFilePath: String? = nil,
        errorMessage: String? = nil
    ) {
        self.completedAt = Date()
        self.exitCode = exitCode
        self.durationSeconds = durationSeconds
        self.logFilePath = logFilePath
        self.errorMessage = errorMessage
        self.status = exitCode == 0 ? .completed : .failed
    }

    /// ログファイルパスを設定（Coordinator用）
    /// 実行完了後にCoordinatorがログファイルパスを登録する際に使用
    public mutating func setLogFilePath(_ path: String) {
        self.logFilePath = path
    }
}
