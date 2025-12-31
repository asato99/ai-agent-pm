// Sources/Domain/Entities/Handoff.swift
// 参照: docs/prd/AGENT_CONCEPT.md - ハンドオフ

import Foundation

/// タスクのハンドオフ（引き継ぎ）を表すエンティティ
/// エージェント間でタスクを引き継ぐ際の情報を記録
public struct Handoff: Identifiable, Equatable, Sendable {
    public let id: HandoffID
    public let taskId: TaskID
    public let fromAgentId: AgentID
    public let toAgentId: AgentID?
    public var summary: String
    public var context: String?
    public var recommendations: String?
    public var acceptedAt: Date?
    public let createdAt: Date

    public init(
        id: HandoffID,
        taskId: TaskID,
        fromAgentId: AgentID,
        toAgentId: AgentID? = nil,
        summary: String,
        context: String? = nil,
        recommendations: String? = nil,
        acceptedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.taskId = taskId
        self.fromAgentId = fromAgentId
        self.toAgentId = toAgentId
        self.summary = summary
        self.context = context
        self.recommendations = recommendations
        self.acceptedAt = acceptedAt
        self.createdAt = createdAt
    }

    /// ハンドオフが承認済みかどうか
    public var isAccepted: Bool {
        acceptedAt != nil
    }

    /// ハンドオフが特定のエージェント宛かどうか
    public var isTargeted: Bool {
        toAgentId != nil
    }

    /// ハンドオフが保留中かどうか
    public var isPending: Bool {
        !isAccepted
    }
}
