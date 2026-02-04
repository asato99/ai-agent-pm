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
    /// タスクを作成したエージェント
    /// 委譲タスク判別用: createdByAgentId != assigneeId → 委譲されたタスク
    public var createdByAgentId: AgentID?
    public var dependencies: [TaskID]
    public var parentTaskId: TaskID?
    public var estimatedMinutes: Int?
    public var actualMinutes: Int?
    public let createdAt: Date
    public var updatedAt: Date
    public var completedAt: Date?

    // MARK: - Completion Result
    /// 完了結果（success / failed / blocked / cancelled）
    public var completionResult: String?
    /// 成果サマリー
    public var completionSummary: String?

    // MARK: - Status Change Tracking
    /// 最後にステータスを変更したエージェント
    /// 参照: docs/plan/BLOCKED_TASK_RECOVERY.md
    public var statusChangedByAgentId: AgentID?
    /// ステータス変更日時
    public var statusChangedAt: Date?
    /// ブロック理由（status == .blocked の場合のみ有効）
    public var blockedReason: String?

    // MARK: - Lock Fields (Internal Audit)
    /// ロック状態（監査エージェントによる強制ロック）
    /// 参照: docs/requirements/AUDIT.md - ロック機能
    public var isLocked: Bool
    /// ロックを行った Internal Audit の ID
    public var lockedByAuditId: InternalAuditID?
    /// ロック日時
    public var lockedAt: Date?

    // MARK: - Approval Fields
    /// 参照: docs/design/TASK_REQUEST_APPROVAL.md - 承認フロー
    /// 依頼者のエージェントID（直接作成時はNULL）
    public var requesterId: AgentID?
    /// 承認ステータス
    public var approvalStatus: ApprovalStatus
    /// 却下理由（rejected時のみ）
    public var rejectedReason: String?
    /// 承認者のエージェントID
    public var approvedBy: AgentID?
    /// 承認日時
    public var approvedAt: Date?

    public init(
        id: TaskID,
        projectId: ProjectID,
        title: String,
        description: String = "",
        status: TaskStatus = .backlog,
        priority: TaskPriority = .medium,
        assigneeId: AgentID? = nil,
        createdByAgentId: AgentID? = nil,
        dependencies: [TaskID] = [],
        parentTaskId: TaskID? = nil,
        estimatedMinutes: Int? = nil,
        actualMinutes: Int? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        completedAt: Date? = nil,
        completionResult: String? = nil,
        completionSummary: String? = nil,
        statusChangedByAgentId: AgentID? = nil,
        statusChangedAt: Date? = nil,
        blockedReason: String? = nil,
        isLocked: Bool = false,
        lockedByAuditId: InternalAuditID? = nil,
        lockedAt: Date? = nil,
        requesterId: AgentID? = nil,
        approvalStatus: ApprovalStatus = .approved,
        rejectedReason: String? = nil,
        approvedBy: AgentID? = nil,
        approvedAt: Date? = nil
    ) {
        self.id = id
        self.projectId = projectId
        self.title = title
        self.description = description
        self.status = status
        self.priority = priority
        self.assigneeId = assigneeId
        self.createdByAgentId = createdByAgentId
        self.dependencies = dependencies
        self.parentTaskId = parentTaskId
        self.estimatedMinutes = estimatedMinutes
        self.actualMinutes = actualMinutes
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.completedAt = completedAt
        self.completionResult = completionResult
        self.completionSummary = completionSummary
        self.statusChangedByAgentId = statusChangedByAgentId
        self.statusChangedAt = statusChangedAt
        self.blockedReason = blockedReason
        self.isLocked = isLocked
        self.lockedByAuditId = lockedByAuditId
        self.lockedAt = lockedAt
        self.requesterId = requesterId
        self.approvalStatus = approvalStatus
        self.rejectedReason = rejectedReason
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
    }

    /// タスクが完了状態かどうか
    public var isCompleted: Bool {
        status == .done || status == .cancelled
    }

    /// タスクがアクティブかどうか（作業中）
    public var isActive: Bool {
        status == .inProgress
    }

    /// ステータス変更が可能かどうか（ロックされていない場合のみ）
    public var canChangeStatus: Bool {
        !isLocked
    }

    /// 承認待ちかどうか
    public var isPendingApproval: Bool {
        approvalStatus == .pendingApproval
    }

    // MARK: - Approval Methods

    /// タスクを承認する
    /// - Parameters:
    ///   - approverId: 承認者のエージェントID
    ///   - date: 承認日時
    public mutating func approve(by approverId: AgentID, at date: Date = Date()) {
        approvalStatus = .approved
        approvedBy = approverId
        approvedAt = date
    }

    /// タスクを却下する
    /// - Parameter reason: 却下理由
    public mutating func reject(reason: String?) {
        approvalStatus = .rejected
        rejectedReason = reason
    }
}

// MARK: - TaskStatus

/// タスクのステータス
/// 要件: backlog, todo, in_progress, done, cancelled, blocked のみ（in_review は削除）
public enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case backlog
    case todo
    case inProgress = "in_progress"
    case blocked
    case done
    case cancelled

    /// 表示用ラベル
    public var displayName: String {
        switch self {
        case .backlog: return "Backlog"
        case .todo: return "To Do"
        case .inProgress: return "In Progress"
        case .blocked: return "Blocked"
        case .done: return "Done"
        case .cancelled: return "Cancelled"
        }
    }

    /// アクティブなステータスかどうか（作業中）
    public var isActive: Bool {
        self == .inProgress
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

// MARK: - ApprovalStatus

/// タスク依頼の承認ステータス
/// 参照: docs/design/TASK_REQUEST_APPROVAL.md
public enum ApprovalStatus: String, Codable, Sendable, CaseIterable {
    case approved
    case pendingApproval = "pending_approval"
    case rejected

    /// 表示用ラベル
    public var displayName: String {
        switch self {
        case .approved: return "Approved"
        case .pendingApproval: return "Pending Approval"
        case .rejected: return "Rejected"
        }
    }
}
