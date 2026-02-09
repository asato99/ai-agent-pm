// Sources/UseCase/Task/TaskCommands.swift
// タスク書き込み系ユースケース

import Foundation
import Domain

// MARK: - CreateTaskUseCase

/// タスク作成ユースケース
public struct CreateTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let projectRepository: any ProjectRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        projectRepository: any ProjectRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.projectRepository = projectRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        projectId: ProjectID,
        title: String,
        description: String = "",
        priority: TaskPriority = .medium,
        assigneeId: AgentID? = nil,
        actorAgentId: AgentID?,
        sessionId: SessionID?
    ) throws -> Task {
        // プロジェクトの存在確認
        guard try projectRepository.findById(projectId) != nil else {
            throw UseCaseError.projectNotFound(projectId)
        }

        // バリデーション
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Title cannot be empty")
        }

        let task = Task(
            id: TaskID.generate(),
            projectId: projectId,
            title: title,
            description: description,
            status: .backlog,
            priority: priority,
            assigneeId: assigneeId
        )

        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .created,
            agentId: actorAgentId,
            sessionId: sessionId,
            newState: task.status.rawValue
        )
        try eventRepository.save(event)

        return task
    }
}

// MARK: - AssignTaskUseCase

/// タスク割り当てユースケース
public struct AssignTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        assigneeId: AgentID?,
        actorAgentId: AgentID?,
        sessionId: SessionID?
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // Feature 13: 担当エージェント再割り当て制限
        // in_progress/blocked タスクは担当変更不可（作業コンテキスト破棄防止）
        let previousAssignee = task.assigneeId
        let isReassignment = previousAssignee != nil && assigneeId != previousAssignee
        if isReassignment && (task.status == .inProgress || task.status == .blocked) {
            throw UseCaseError.reassignmentNotAllowed(taskId: taskId, status: task.status)
        }

        // 割り当て先エージェントの存在確認
        if let assigneeId = assigneeId {
            guard try agentRepository.findById(assigneeId) != nil else {
                throw UseCaseError.agentNotFound(assigneeId)
            }
        }
        task.assigneeId = assigneeId
        task.updatedAt = Date()

        try taskRepository.save(task)

        // イベント記録
        let eventType: EventType = assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: actorAgentId,
            sessionId: sessionId,
            previousState: previousAssignee?.value,
            newState: assigneeId?.value
        )
        try eventRepository.save(event)

        return task
    }
}

// MARK: - UpdateTaskUseCase

/// タスク更新ユースケース
public struct UpdateTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(
        taskId: TaskID,
        title: String? = nil,
        description: String? = nil,
        priority: TaskPriority? = nil,
        assigneeId: AgentID? = nil,
        clearAssignee: Bool = false,
        estimatedMinutes: Int? = nil,
        actualMinutes: Int? = nil
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        if let title = title {
            task.title = title
        }
        if let description = description {
            task.description = description
        }
        if let priority = priority {
            task.priority = priority
        }
        if let assigneeId = assigneeId {
            task.assigneeId = assigneeId
        } else if clearAssignee {
            task.assigneeId = nil
        }
        if let estimatedMinutes = estimatedMinutes {
            task.estimatedMinutes = estimatedMinutes
        }
        if let actualMinutes = actualMinutes {
            task.actualMinutes = actualMinutes
        }

        task.updatedAt = Date()
        try taskRepository.save(task)
        return task
    }
}

// MARK: - ApproveTaskUseCase
// 参照: docs/design/TASK_REQUEST_APPROVAL.md

/// タスク承認ユースケース
/// 承認者が担当者の祖先であることを確認し、タスクを承認する
public struct ApproveTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        approverId: AgentID
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 承認待ち状態の確認
        guard task.approvalStatus == .pendingApproval else {
            throw UseCaseError.validationFailed("Task is not pending approval")
        }

        // 担当者の確認
        guard let assigneeId = task.assigneeId else {
            throw UseCaseError.validationFailed("Task has no assignee")
        }

        // 承認者が担当者の祖先であることを確認
        let allAgents = try agentRepository.findAll()
        let agentsDict = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        guard AgentHierarchy.isAncestorOf(ancestor: approverId, descendant: assigneeId, agents: agentsDict) else {
            throw UseCaseError.permissionDenied("You are not authorized to approve this task")
        }

        // 承認処理
        task.approve(by: approverId)
        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: approverId,
            previousState: ApprovalStatus.pendingApproval.rawValue,
            newState: ApprovalStatus.approved.rawValue,
            reason: "Task approved"
        )
        try eventRepository.save(event)

        return task
    }
}

// MARK: - RejectTaskUseCase
// 参照: docs/design/TASK_REQUEST_APPROVAL.md

/// タスク却下ユースケース
/// 却下者が担当者の祖先であることを確認し、タスクを却下する
public struct RejectTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        rejecterId: AgentID,
        reason: String?
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 承認待ち状態の確認
        guard task.approvalStatus == .pendingApproval else {
            throw UseCaseError.validationFailed("Task is not pending approval")
        }

        // 担当者の確認
        guard let assigneeId = task.assigneeId else {
            throw UseCaseError.validationFailed("Task has no assignee")
        }

        // 却下者が担当者の祖先であることを確認
        let allAgents = try agentRepository.findAll()
        let agentsDict = Dictionary(uniqueKeysWithValues: allAgents.map { ($0.id, $0) })
        guard AgentHierarchy.isAncestorOf(ancestor: rejecterId, descendant: assigneeId, agents: agentsDict) else {
            throw UseCaseError.permissionDenied("You are not authorized to reject this task")
        }

        // 却下処理
        task.reject(reason: reason)
        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: rejecterId,
            previousState: ApprovalStatus.pendingApproval.rawValue,
            newState: ApprovalStatus.rejected.rawValue,
            reason: reason ?? "Task rejected"
        )
        try eventRepository.save(event)

        return task
    }
}
