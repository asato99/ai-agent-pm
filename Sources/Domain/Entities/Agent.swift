// Sources/Domain/Entities/Agent.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Agent Entity
// 参照: docs/prd/AGENT_CONCEPT.md - エージェント概念

import Foundation

/// AIエージェントまたは人間を表すエンティティ
/// 要件: エージェントはトップレベルエンティティ（プロジェクト非依存）、階層構造をサポート
public struct Agent: Identifiable, Equatable, Sendable {
    public let id: AgentID
    public var name: String
    public var role: String
    public var type: AgentType
    public var roleType: AgentRoleType
    public var parentAgentId: AgentID?      // 階層構造（親エージェント）
    public var maxParallelTasks: Int        // 同時実行可能タスク数
    public var capabilities: [String]
    public var systemPrompt: String?
    public var status: AgentStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: AgentID,
        name: String,
        role: String,
        type: AgentType = .ai,
        roleType: AgentRoleType = .developer,
        parentAgentId: AgentID? = nil,
        maxParallelTasks: Int = 1,
        capabilities: [String] = [],
        systemPrompt: String? = nil,
        status: AgentStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.roleType = roleType
        self.parentAgentId = parentAgentId
        self.maxParallelTasks = maxParallelTasks
        self.capabilities = capabilities
        self.systemPrompt = systemPrompt
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - AgentType

/// エージェントの種別
public enum AgentType: String, Codable, Sendable, CaseIterable {
    case human
    case ai

    public var displayName: String {
        switch self {
        case .human: return "Human"
        case .ai: return "AI"
        }
    }
}

// MARK: - AgentRoleType

/// エージェントの役割タイプ
public enum AgentRoleType: String, Codable, Sendable, CaseIterable {
    case developer
    case reviewer
    case tester
    case architect
    case manager
    case writer
    case designer
    case analyst

    public var displayName: String {
        switch self {
        case .developer: return "Developer"
        case .reviewer: return "Reviewer"
        case .tester: return "Tester"
        case .architect: return "Architect"
        case .manager: return "Manager"
        case .writer: return "Writer"
        case .designer: return "Designer"
        case .analyst: return "Analyst"
        }
    }
}

// MARK: - AgentStatus

/// エージェントのステータス
/// PRD: AGENT_CONCEPT.md - Active / Inactive / Archived
public enum AgentStatus: String, Codable, Sendable, CaseIterable {
    case active
    case inactive
    case suspended  // 一時停止
    case archived   // アーカイブ済み（削除済み、履歴保持）

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .suspended: return "Suspended"
        case .archived: return "Archived"
        }
    }
}
