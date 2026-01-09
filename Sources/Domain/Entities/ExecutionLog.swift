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

    // MARK: - Model Verification Fields
    /// Agent Instanceが申告したプロバイダー
    public private(set) var reportedProvider: String?
    /// Agent Instanceが申告したモデルID
    public private(set) var reportedModel: String?
    /// モデル検証結果（nil=未検証, true=一致, false=不一致）
    public private(set) var modelVerified: Bool?

    /// 新しい実行ログを作成（実行開始時）
    public init(
        id: ExecutionLogID = .generate(),
        taskId: TaskID,
        agentId: AgentID,
        startedAt: Date = Date(),
        reportedProvider: String? = nil,
        reportedModel: String? = nil,
        modelVerified: Bool? = nil
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
        self.reportedProvider = reportedProvider
        self.reportedModel = reportedModel
        self.modelVerified = modelVerified
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
        errorMessage: String?,
        reportedProvider: String? = nil,
        reportedModel: String? = nil,
        modelVerified: Bool? = nil
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
        self.reportedProvider = reportedProvider
        self.reportedModel = reportedModel
        self.modelVerified = modelVerified
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

    /// モデル情報を設定
    /// report_model 呼び出し後にセッションからコピーする際に使用
    public mutating func setModelInfo(
        provider: String?,
        model: String?,
        verified: Bool?
    ) {
        self.reportedProvider = provider
        self.reportedModel = model
        self.modelVerified = verified
    }
}
