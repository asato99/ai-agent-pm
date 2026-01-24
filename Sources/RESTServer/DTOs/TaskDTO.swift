// Sources/RESTServer/DTOs/TaskDTO.swift
// AI Agent PM - REST API Server

import Foundation
import Domain

/// Task data transfer object for REST API
/// Note: Uses Swift's default camelCase JSON encoding (no CodingKeys)
public struct TaskDTO: Codable {
    let id: String
    let projectId: String
    let title: String
    let description: String
    let status: String
    let priority: String
    let assigneeId: String?
    let dependencies: [String]
    let dependentTasks: [String]?  // Phase 4: 逆依存関係（このタスクに依存するタスク）
    let parentTaskId: String?
    let estimatedMinutes: Int?     // Phase 2: 見積もり時間（分）
    let actualMinutes: Int?        // Phase 2: 実績時間（分）
    let blockedReason: String?     // Phase 3: ブロック理由
    let approvalStatus: String     // Task Request/Approval: 承認状態
    let requesterId: String?       // Task Request/Approval: 依頼者ID
    let rejectedReason: String?    // Task Request/Approval: 却下理由
    let createdAt: String
    let updatedAt: String

    init(from task: Task, dependentTasks: [String]? = nil) {
        self.id = task.id.value
        self.projectId = task.projectId.value
        self.title = task.title
        self.description = task.description
        self.status = task.status.rawValue
        self.priority = task.priority.rawValue
        self.assigneeId = task.assigneeId?.value
        self.dependencies = task.dependencies.map { $0.value }
        self.dependentTasks = dependentTasks
        self.parentTaskId = task.parentTaskId?.value
        self.estimatedMinutes = task.estimatedMinutes
        self.actualMinutes = task.actualMinutes
        self.blockedReason = task.blockedReason
        self.approvalStatus = task.approvalStatus.rawValue
        self.requesterId = task.requesterId?.value
        self.rejectedReason = task.rejectedReason
        self.createdAt = ISO8601DateFormatter().string(from: task.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: task.updatedAt)
    }
}

/// Request body for creating a task
public struct CreateTaskRequest: Decodable {
    public let title: String
    public let description: String?
    public let priority: String?
    public let assigneeId: String?
    public let dependencies: [String]?
}

/// Request body for updating a task
public struct UpdateTaskRequest: Decodable {
    public let title: String?
    public let description: String?
    public let status: String?
    public let priority: String?
    public let assigneeId: String?
    public let dependencies: [String]?
    public let estimatedMinutes: Int?    // Phase 2: 見積もり時間（分）
    public let actualMinutes: Int?       // Phase 2: 実績時間（分）
    public let blockedReason: String?    // Phase 3: ブロック理由
}

// MARK: - Task Request/Approval DTOs
// 参照: docs/design/TASK_REQUEST_APPROVAL.md

/// Request body for creating a task request
public struct RequestTaskRequest: Decodable {
    public let title: String
    public let description: String?
    public let assigneeId: String
    public let priority: String?

    enum CodingKeys: String, CodingKey {
        case title
        case description
        case assigneeId = "assignee_id"
        case priority
    }
}

/// Request body for rejecting a task request
public struct RejectTaskRequest: Decodable {
    public let reason: String?
}

/// Response for task request creation
public struct TaskRequestResponseDTO: Encodable {
    public let taskId: String
    public let approvalStatus: String
    public let status: String?  // backlog when approved
    public let approvers: [String]?  // approver IDs when pending

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case approvalStatus = "approval_status"
        case status
        case approvers
    }
}

/// Response for task approval
public struct TaskApprovalResponseDTO: Encodable {
    public let taskId: String
    public let approvalStatus: String
    public let status: String
    public let approvedBy: String
    public let approvedAt: String

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case approvalStatus = "approval_status"
        case status
        case approvedBy = "approved_by"
        case approvedAt = "approved_at"
    }
}

/// Response for task rejection
public struct TaskRejectionResponseDTO: Encodable {
    public let taskId: String
    public let approvalStatus: String
    public let rejectedReason: String?

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case approvalStatus = "approval_status"
        case rejectedReason = "rejected_reason"
    }
}

/// Task DTO with approval information
public struct TaskWithApprovalDTO: Encodable {
    public let id: String
    public let projectId: String
    public let title: String
    public let description: String
    public let status: String
    public let priority: String
    public let assigneeId: String?
    public let requesterId: String?
    public let approvalStatus: String
    public let rejectedReason: String?
    public let createdAt: String
    public let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case title
        case description
        case status
        case priority
        case assigneeId = "assignee_id"
        case requesterId = "requester_id"
        case approvalStatus = "approval_status"
        case rejectedReason = "rejected_reason"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    public init(from task: Task) {
        self.id = task.id.value
        self.projectId = task.projectId.value
        self.title = task.title
        self.description = task.description
        self.status = task.status.rawValue
        self.priority = task.priority.rawValue
        self.assigneeId = task.assigneeId?.value
        self.requesterId = task.requesterId?.value
        self.approvalStatus = task.approvalStatus.rawValue
        self.rejectedReason = task.rejectedReason
        self.createdAt = ISO8601DateFormatter().string(from: task.createdAt)
        self.updatedAt = ISO8601DateFormatter().string(from: task.updatedAt)
    }
}
