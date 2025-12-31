// Sources/Domain/Entities/Task.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Task Entity
// 参照: docs/prd/TASK_MANAGEMENT.md - タスクステータスフロー

import Foundation

/// タスクを表すエンティティ
/// Phase 1では最小限のプロパティのみ実装
public struct Task: Identifiable, Equatable, Sendable {
    public let id: TaskID
    public let projectId: ProjectID
    public var title: String
    public var status: TaskStatus
    public var assigneeId: AgentID?

    public init(
        id: TaskID,
        projectId: ProjectID,
        title: String,
        status: TaskStatus = .backlog,
        assigneeId: AgentID? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.status = status
        self.assigneeId = assigneeId
    }
}

// MARK: - TaskStatus

/// タスクのステータス
/// 参照: docs/prd/TASK_MANAGEMENT.md - ステータスフロー図
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case done

    /// 表示用ラベル
    public var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .done: return "Done"
        }
    }
}
