// Sources/Domain/Entities/Agent.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Agent Entity
// 参照: docs/prd/AGENT_CONCEPT.md - エージェント概念

import Foundation

/// AIエージェントまたは人間を表すエンティティ
/// Phase 1では最小限のプロパティのみ実装
public struct Agent: Identifiable, Equatable, Sendable {
    public let id: AgentID
    public var name: String
    public var role: String
    public var type: AgentType

    public init(
        id: AgentID,
        name: String,
        role: String,
        type: AgentType
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
    }
}

// MARK: - AgentType

/// エージェントの種別
/// 参照: docs/prd/AGENT_CONCEPT.md - AgentType
public enum AgentType: String, Codable, Sendable, CaseIterable {
    case human
    case ai
}
