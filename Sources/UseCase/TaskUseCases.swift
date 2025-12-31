// Sources/UseCase/TaskUseCases.swift
// タスク関連のユースケース

import Foundation
import Domain

// MARK: - UpdateTaskStatusUseCase

/// タスクステータス更新ユースケース
public struct UpdateTaskStatusUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        newStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String?
    ) throws -> Task {
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let previousStatus = task.status

        // ステータス遷移の検証
        guard Self.canTransition(from: previousStatus, to: newStatus) else {
            throw UseCaseError.invalidStatusTransition(from: previousStatus, to: newStatus)
        }

        task.status = newStatus
        task.updatedAt = Date()

        if newStatus == .done {
            task.completedAt = Date()
        }

        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .statusChanged,
            agentId: agentId,
            sessionId: sessionId,
            previousState: previousStatus.rawValue,
            newState: task.status.rawValue,
            reason: reason
        )
        try eventRepository.save(event)

        return task
    }

    /// ステータス遷移が有効かどうかを検証
    public static func canTransition(from: TaskStatus, to: TaskStatus) -> Bool {
        // 同じステータスへの遷移は不可
        if from == to { return false }

        switch (from, to) {
        case (.backlog, .todo), (.backlog, .cancelled):
            return true
        case (.todo, .inProgress), (.todo, .backlog), (.todo, .cancelled):
            return true
        case (.inProgress, .inReview), (.inProgress, .blocked), (.inProgress, .todo):
            return true
        case (.inReview, .done), (.inReview, .inProgress):
            return true
        case (.blocked, .inProgress), (.blocked, .cancelled):
            return true
        case (.done, _), (.cancelled, _):
            return false // 完了・キャンセル済みからは遷移不可
        default:
            return false
        }
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

        // 割り当て先エージェントの存在確認
        if let assigneeId = assigneeId {
            guard try agentRepository.findById(assigneeId) != nil else {
                throw UseCaseError.agentNotFound(assigneeId)
            }
        }

        let previousAssignee = task.assigneeId
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

// MARK: - GetMyTasksUseCase

/// 自分のタスク取得ユースケース
public struct GetMyTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(agentId: AgentID) throws -> [Task] {
        try taskRepository.findByAssignee(agentId)
    }
}
