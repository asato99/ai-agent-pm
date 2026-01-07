// Sources/Domain/Entities/ProjectAgentAssignment.swift
// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
// 参照: docs/usecase/UC004_MultiProjectSameAgent.md

import Foundation

/// プロジェクトへのエージェント割り当てを表すエンティティ
/// 複合主キー: (project_id, agent_id)
public struct ProjectAgentAssignment: Equatable, Sendable {
    public let projectId: ProjectID
    public let agentId: AgentID
    public let assignedAt: Date

    /// 新しい割り当てを作成
    public init(
        projectId: ProjectID,
        agentId: AgentID,
        assignedAt: Date = Date()
    ) {
        self.projectId = projectId
        self.agentId = agentId
        self.assignedAt = assignedAt
    }
}
