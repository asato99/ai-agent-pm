// Sources/Domain/Entities/InternalAudit.swift
// 参照: docs/requirements/AUDIT.md - Internal Audit 仕様

import Foundation

// MARK: - InternalAudit

/// Internal Audit エンティティ
/// プロジェクト横断でプロセス遵守を自動監視する仕組み
/// 要件: プロジェクトと同様に複数登録可能なトップレベルエンティティ
public struct InternalAudit: Identifiable, Equatable, Sendable {
    public let id: InternalAuditID
    public var name: String
    public var description: String?
    public var status: AuditStatus
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: InternalAuditID,
        name: String,
        description: String? = nil,
        status: AuditStatus = .active,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.status = status
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// 監査が有効かどうか
    public var isActive: Bool {
        status == .active
    }
}

// MARK: - AuditStatus

/// Internal Audit のステータス
/// 参照: docs/requirements/AUDIT.md - Internal Audit の状態
public enum AuditStatus: String, Codable, Sendable, CaseIterable {
    case active     // 監査機能が有効。トリガー発火時にワークフロー実行
    case inactive   // 監査機能が無効。トリガーは無視される
    case suspended  // 一時停止。手動で再開可能

    public var displayName: String {
        switch self {
        case .active: return "Active"
        case .inactive: return "Inactive"
        case .suspended: return "Suspended"
        }
    }
}

// MARK: - AuditRule

/// Audit Rule エンティティ
/// Internal Audit のメインエンティティ - トリガー付きワークフロー
/// 要件: トリガー条件 + ワークフローテンプレート + タスク別エージェント割り当て
public struct AuditRule: Identifiable, Equatable, Sendable {
    public let id: AuditRuleID
    public var auditId: InternalAuditID
    public var name: String
    public var triggerType: TriggerType
    public var triggerConfig: [String: Any]?
    public var workflowTemplateId: WorkflowTemplateID
    public var taskAssignments: [TaskAssignment]
    public var isEnabled: Bool
    public let createdAt: Date
    public var updatedAt: Date

    public init(
        id: AuditRuleID,
        auditId: InternalAuditID,
        name: String,
        triggerType: TriggerType,
        triggerConfig: [String: Any]? = nil,
        workflowTemplateId: WorkflowTemplateID,
        taskAssignments: [TaskAssignment],
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.auditId = auditId
        self.name = name
        self.triggerType = triggerType
        self.triggerConfig = triggerConfig
        self.workflowTemplateId = workflowTemplateId
        self.taskAssignments = taskAssignments
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// タスク割り当てがあるかどうか
    public var hasAssignments: Bool {
        !taskAssignments.isEmpty
    }

    // MARK: - Equatable (triggerConfigを除外)

    public static func == (lhs: AuditRule, rhs: AuditRule) -> Bool {
        lhs.id == rhs.id &&
        lhs.auditId == rhs.auditId &&
        lhs.name == rhs.name &&
        lhs.triggerType == rhs.triggerType &&
        lhs.workflowTemplateId == rhs.workflowTemplateId &&
        lhs.taskAssignments == rhs.taskAssignments &&
        lhs.isEnabled == rhs.isEnabled &&
        lhs.createdAt == rhs.createdAt &&
        lhs.updatedAt == rhs.updatedAt
    }
}

// MARK: - TriggerType

/// Audit Rule のトリガー種別
/// 参照: docs/requirements/AUDIT.md - トリガー条件
public enum TriggerType: String, Codable, Sendable, CaseIterable {
    case taskCompleted = "task_completed"           // タスク完了時
    case statusChanged = "status_changed"           // ステータス変更時
    case handoffCompleted = "handoff_completed"     // ハンドオフ完了時
    case deadlineExceeded = "deadline_exceeded"     // 期限超過時

    public var displayName: String {
        switch self {
        case .taskCompleted: return "Task Completed"
        case .statusChanged: return "Status Changed"
        case .handoffCompleted: return "Handoff Completed"
        case .deadlineExceeded: return "Deadline Exceeded"
        }
    }
}

// MARK: - TaskAssignment

/// Audit Rule 内のタスク別エージェント割り当て
/// 参照: docs/requirements/AUDIT.md - TaskAssignment
public struct TaskAssignment: Equatable, Codable, Sendable {
    public let templateTaskOrder: Int   // テンプレートタスクのorder
    public let agentId: AgentID         // 割り当てるエージェント

    public init(templateTaskOrder: Int, agentId: AgentID) {
        self.templateTaskOrder = templateTaskOrder
        self.agentId = agentId
    }
}
