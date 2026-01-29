// Sources/Domain/Entities/AgentSkillAssignment.swift
// 参照: docs/design/AGENT_SKILLS.md - エージェントスキル割り当て

import Foundation

/// エージェントとスキルの割り当て（多対多関係）
/// 参照: docs/design/AGENT_SKILLS.md - Section 3.2
public struct AgentSkillAssignment: Equatable, Sendable {
    /// 割り当て先のエージェントID
    public let agentId: AgentID
    /// 割り当てられたスキルID
    public let skillId: SkillID
    /// 割り当て日時
    public let assignedAt: Date

    public init(
        agentId: AgentID,
        skillId: SkillID,
        assignedAt: Date = Date()
    ) {
        self.agentId = agentId
        self.skillId = skillId
        self.assignedAt = assignedAt
    }
}
