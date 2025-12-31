// Sources/Domain/Entities/Task.swift
// 参照: docs/architecture/DOMAIN_MODEL.md - Task Entity
// 参照: docs/prd/TASK_MANAGEMENT.md - タスクステータスフロー

import Foundation

/// タスクを表すエンティティ
public struct Task: Identifiable, Equatable, Sendable {
    public let id: TaskID
    public let projectId: ProjectID
    public var title: String
    public var description: String
    public var status: TaskStatus
    public var priority: TaskPriority
    public var assigneeId: AgentID?
    public var parentTaskId: TaskID?
    public var dependencies: [TaskID]
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    public init(
        id: TaskID,
        projectId: ProjectID,
        title: String,
        description: String = "",
        status: TaskStatus = .backlog,
        priority: TaskPriority = .medium,
        assigneeId: AgentID? = nil,
        parentTaskId: TaskID? = nil,
        dependencies: [TaskID] = [],
        estimatedMinutes: Int? = nil,
        actualMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeId = assigneeId
        self.parentTaskId = parentTaskId
        self.dependencies = dependencies
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
    }

    /// タスクが完了状態かどうか
    public var isCompleted: Bool {
        status == .done || status == .cancelled
    }

    /// タスクがアクティブかどうか
    public var isActive: Bool {
        status == .inProgress || status == .inReview
    }
}

// MARK: - TaskStatus

/// タスクのステータス
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case inReview = "in_review"
    case blocked
    case done
    case cancelled

    /// 表示用ラベル
    public var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "Todo"
        case .inProgress: return "In Progress"
        case .inReview: return "In Review"
        case .blocked: return "Blocked"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    /// アクティブなステータスかどうか
    public var isActive: Bool {
        self == .inProgress || self == .inReview
    }

    /// 完了状態かどうか
    public var isCompleted: Bool {
        self == .done || self == .cancelled
    }
}

// MARK: - TaskPriority

/// タスクの優先度
/// PRD: Priority { low, medium, high, urgent }
public enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case urgent
    case high
    case medium
    case low

    public var displayName: String {
        switch self {
        case .urgent: return "Urgent"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }

    /// ソート用の数値（高いほど優先度が高い）
    public var sortOrder: Int {
        switch self {
        case .urgent: return 4
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        }
    }
}
