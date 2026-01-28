// Sources/Domain/Entities/ProjectAgentAssignment.swift
// 参照: docs/requirements/PROJECTS.md - エージェント割り当て
// 参照: docs/usecase/UC004_MultiProjectSameAgent.md
// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md - スポーン管理

import Foundation

/// プロジェクトへのエージェント割り当てを表すエンティティ
/// 複合主キー: (project_id, agent_id)
public struct ProjectAgentAssignment: Equatable, Sendable {
    public let projectId: ProjectID
    public let agentId: AgentID
    public let assignedAt: Date
    /// スポーン開始時刻（nil = スポーン中でない）
    /// 参照: docs/design/SESSION_SPAWN_ARCHITECTURE.md
    public let spawnStartedAt: Date?

    /// 新しい割り当てを作成
    public init(
        projectId: ProjectID,
        agentId: AgentID,
        assignedAt: Date = Date(),
        spawnStartedAt: Date? = nil
    ) {
        self.projectId = projectId
        self.agentId = agentId
        self.assignedAt = assignedAt
        self.spawnStartedAt = spawnStartedAt
    }
}
