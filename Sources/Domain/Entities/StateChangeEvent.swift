// Sources/Domain/Entities/StateChangeEvent.swift
// 参照: docs/prd/STATE_HISTORY.md - イベントソーシング

import Foundation

/// 状態変更イベントを表すエンティティ
/// イベントソーシングによる履歴追跡のための記録
public struct StateChangeEvent: Identifiable, Equatable, Sendable {
    public let id: EventID
    public let projectId: ProjectID
    public let entityType: EntityType
    public let entityId: String
    public let eventType: EventType
    public let agentId: AgentID?
    public let sessionId: SessionID?
    public let previousState: String?
    public let newState: String?
    public let reason: String?
    public let metadata: [String: String]?
    public let timestamp: Date

    public init(
        id: EventID,
        projectId: ProjectID,
        entityType: EntityType,
        entityId: String,
        eventType: EventType,
        agentId: AgentID? = nil,
        sessionId: SessionID? = nil,
        previousState: String? = nil,
        newState: String? = nil,
        reason: String? = nil,
        metadata: [String: String]? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.projectId = projectId
        self.entityType = entityType
        self.entityId = entityId
        self.eventType = eventType
        self.agentId = agentId
        self.sessionId = sessionId
        self.previousState = previousState
        self.newState = newState
        self.reason = reason
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

// MARK: - EntityType

/// エンティティの種類
/// 要件: subtask は削除（タスク間の関係は依存関係のみで表現）
public enum EntityType: String, Codable, Sendable {
    case project
    case task
    case agent
    case session
    case context
    case handoff

    public var displayName: String {
        switch self {
        case .project: return "Project"
        case .task: return "Task"
        case .agent: return "Agent"
        case .session: return "Session"
        case .context: return "Context"
        case .handoff: return "Handoff"
        }
    }
}

// MARK: - EventType

/// イベントの種類
public enum EventType: String, Codable, Sendable {
    case created
    case updated
    case deleted
    case statusChanged = "status_changed"
    case assigned
    case unassigned
    case started
    case completed
    case kicked = "agent_kicked"

    public var displayName: String {
        switch self {
        case .created: return "Created"
        case .updated: return "Updated"
        case .deleted: return "Deleted"
        case .statusChanged: return "Status Changed"
        case .assigned: return "Assigned"
        case .unassigned: return "Unassigned"
        case .started: return "Started"
        case .completed: return "Completed"
        case .kicked: return "Agent Kicked"
        }
    }
}
