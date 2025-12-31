// Sources/Domain/Entities/Context.swift
// 参照: docs/prd/STATE_HISTORY.md - コンテキスト管理

import Foundation

/// タスクに対するコンテキスト情報を表すエンティティ
/// エージェントがタスクに取り組む際の進捗、発見事項、ブロッカー等を記録
public struct Context: Identifiable, Equatable, Sendable {
    public let id: ContextID
    public let taskId: TaskID
    public let sessionId: SessionID
    public let agentId: AgentID
    public var progress: String?
    public var findings: String?
    public var blockers: String?
    public var nextSteps: String?
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: ContextID,
        taskId: TaskID,
        sessionId: SessionID,
        agentId: AgentID,
        progress: String? = nil,
        findings: String? = nil,
        blockers: String? = nil,
        nextSteps: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.sessionId = sessionId
        self.agentId = agentId
        self.progress = progress
        self.findings = findings
        self.blockers = blockers
        self.nextSteps = nextSteps
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// コンテキストが空かどうか
    public var isEmpty: Bool {
        progress == nil && findings == nil && blockers == nil && nextSteps == nil
    }

    /// ブロッカーがあるかどうか
    public var hasBlockers: Bool {
        guard let blockers = blockers else { return false }
        return !blockers.isEmpty
    }
}
