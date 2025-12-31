// Sources/Domain/Entities/Session.swift
// 参照: docs/prd/AGENT_CONCEPT.md - セッション管理

import Foundation

/// エージェントの作業セッションを表すエンティティ
public struct Session: Identifiable, Equatable, Sendable {
    public let id: SessionID
    public let projectId: ProjectID
    public let agentId: AgentID
    public let startedAt: Date
    public var endedAt: Date?
    public var status: SessionStatus

    public init(
        id: SessionID,
        projectId: ProjectID,
        agentId: AgentID,
        startedAt: Date = Date(),
        endedAt: Date? = nil,
        status: SessionStatus = .active
    ) {
        self.id = id
        self.projectId = projectId
        self.agentId = agentId
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.status = status
    }

    /// セッションがアクティブかどうか
    public var isActive: Bool {
        status == .active
    }

    /// セッションの継続時間（秒）
    public var duration: TimeInterval? {
        guard let endedAt = endedAt else {
            return Date().timeIntervalSince(startedAt)
        }
        return endedAt.timeIntervalSince(startedAt)
    }
}

// MARK: - SessionStatus

/// セッションのステータス
public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case active
    case completed
    case abandoned

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .completed: return "Completed"
        case .abandoned: return "Abandoned"
        }
    }
}
