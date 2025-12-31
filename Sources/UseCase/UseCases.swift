// Sources/UseCase/UseCases.swift
// UseCase層のエントリポイント

import Foundation
import Domain

// MARK: - UseCase Errors

/// UseCase層で発生するエラー
public enum UseCaseError: Error, Sendable {
    case taskNotFound(TaskID)
    case agentNotFound(AgentID)
    case projectNotFound(ProjectID)
    case sessionNotFound(SessionID)
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case sessionNotActive
    case sessionAlreadyActive(SessionID)
    case unauthorized
    case validationFailed(String)
}

extension UseCaseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .taskNotFound(let id):
            return "Task not found: \(id.value)"
        case .agentNotFound(let id):
            return "Agent not found: \(id.value)"
        case .projectNotFound(let id):
            return "Project not found: \(id.value)"
        case .sessionNotFound(let id):
            return "Session not found: \(id.value)"
        case .invalidStatusTransition(let from, let to):
            return "Invalid status transition: \(from.rawValue) -> \(to.rawValue)"
        case .sessionNotActive:
            return "No active session"
        case .sessionAlreadyActive(let id):
            return "Session already active: \(id.value)"
        case .unauthorized:
            return "Unauthorized operation"
        case .validationFailed(let message):
            return "Validation failed: \(message)"
        }
    }
}

// MARK: - Project UseCases

/// プロジェクト一覧取得ユースケース
public struct GetProjectsUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol

    public init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    public func execute() throws -> [Project] {
        try projectRepository.findAll()
    }
}

/// プロジェクト作成ユースケース
public struct CreateProjectUseCase: Sendable {
    private let projectRepository: any ProjectRepositoryProtocol

    public init(projectRepository: any ProjectRepositoryProtocol) {
        self.projectRepository = projectRepository
    }

    public func execute(name: String, description: String? = nil) throws -> Project {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let project = Project(
            id: ProjectID.generate(),
            name: name,
            description: description ?? ""
        )

        try projectRepository.save(project)
        return project
    }
}

// MARK: - Agent UseCases

/// エージェント一覧取得ユースケース
public struct GetAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(projectId: ProjectID) throws -> [Agent] {
        try agentRepository.findByProject(projectId)
    }
}

/// エージェント作成ユースケース
public struct CreateAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(
        projectId: ProjectID,
        name: String,
        role: String,
        roleType: AgentRoleType = .developer,
        type: AgentType = .ai,
        systemPrompt: String? = nil
    ) throws -> Agent {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let agent = Agent(
            id: AgentID.generate(),
            projectId: projectId,
            name: name,
            role: role,
            type: type,
            roleType: roleType,
            systemPrompt: systemPrompt
        )

        try agentRepository.save(agent)
        return agent
    }
}

/// エージェントプロファイル取得ユースケース
public struct GetAgentProfileUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(agentId: AgentID) throws -> Agent {
        guard let agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }
        return agent
    }
}

// MARK: - Task UseCases (Additional)

/// タスク一覧取得ユースケース
public struct GetTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(projectId: ProjectID, status: TaskStatus?) throws -> [Task] {
        try taskRepository.findByProject(projectId, status: status)
    }
}

/// 担当者でタスク取得ユースケース
public struct GetTasksByAssigneeUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(assigneeId: AgentID) throws -> [Task] {
        try taskRepository.findByAssignee(assigneeId)
    }
}

/// タスク詳細取得ユースケース
public struct GetTaskDetailUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let subtaskRepository: any SubtaskRepositoryProtocol
    private let contextRepository: any ContextRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        subtaskRepository: any SubtaskRepositoryProtocol,
        contextRepository: any ContextRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.subtaskRepository = subtaskRepository
        self.contextRepository = contextRepository
    }

    public struct Result: Sendable {
        public let task: Task
        public let subtasks: [Subtask]
        public let contexts: [Context]
    }

    public func execute(taskId: TaskID) throws -> Result {
        guard let task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let subtasks = try subtaskRepository.findByTask(taskId)
        let contexts = try contextRepository.findByTask(taskId)

        return Result(task: task, subtasks: subtasks, contexts: contexts)
    }
}

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

// MARK: - Session UseCases (Additional)

/// エージェントのセッション履歴取得ユースケース
public struct GetAgentSessionsUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol

    public init(sessionRepository: any SessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    public func execute(agentId: AgentID) throws -> [Session] {
        try sessionRepository.findByAgent(agentId)
    }
}
