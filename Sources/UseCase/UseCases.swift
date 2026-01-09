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
    case templateNotFound(WorkflowTemplateID)
    case internalAuditNotFound(InternalAuditID)
    case auditRuleNotFound(AuditRuleID)
    case invalidStatusTransition(from: TaskStatus, to: TaskStatus)
    case sessionNotActive
    case sessionAlreadyActive(SessionID)
    case unauthorized
    case validationFailed(String)

    // 認証エラー (Phase 3-1)
    case invalidCredentials
    case credentialNotFound(AgentID)
    case sessionExpired

    // 依存関係ブロック
    case dependencyNotComplete(taskId: TaskID, blockedByTasks: [TaskID])

    // リソース可用性ブロック
    case maxParallelTasksReached(agentId: AgentID, maxParallel: Int, currentCount: Int)

    // 実行ログエラー (Phase 3-3)
    case executionLogNotFound(ExecutionLogID)
    case invalidStateTransition(String)
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
        case .templateNotFound(let id):
            return "Workflow template not found: \(id.value)"
        case .internalAuditNotFound(let id):
            return "Internal audit not found: \(id.value)"
        case .auditRuleNotFound(let id):
            return "Audit rule not found: \(id.value)"
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
        case .invalidCredentials:
            return "Invalid agent_id or passkey"
        case .credentialNotFound(let agentId):
            return "Credential not found for agent: \(agentId.value)"
        case .sessionExpired:
            return "Session has expired"
        case .dependencyNotComplete(let taskId, let blockedByTasks):
            let blockedIds = blockedByTasks.map { $0.value }.joined(separator: ", ")
            return "Task \(taskId.value) is blocked by incomplete dependencies: \(blockedIds)"
        case .maxParallelTasksReached(let agentId, let maxParallel, let currentCount):
            return "Agent \(agentId.value) has reached max parallel tasks limit (\(currentCount)/\(maxParallel))"
        case .executionLogNotFound(let id):
            return "Execution log not found: \(id.value)"
        case .invalidStateTransition(let message):
            return "Invalid state transition: \(message)"
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

    public func execute(name: String, description: String? = nil, workingDirectory: String? = nil) throws -> Project {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let project = Project(
            id: ProjectID.generate(),
            name: name,
            description: description ?? "",
            workingDirectory: workingDirectory?.isEmpty == true ? nil : workingDirectory
        )

        try projectRepository.save(project)
        return project
    }
}

// MARK: - Agent UseCases

/// エージェント一覧取得ユースケース
/// 要件: エージェントはプロジェクト非依存
public struct GetAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute() throws -> [Agent] {
        try agentRepository.findAll()
    }
}

/// エージェント作成ユースケース
/// 要件: エージェントはプロジェクト非依存、階層構造をサポート
public struct CreateAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(
        name: String,
        role: String,
        hierarchyType: AgentHierarchyType = .worker,
        roleType: AgentRoleType = .developer,
        type: AgentType = .ai,
        aiType: AIType? = nil,
        parentAgentId: AgentID? = nil,
        maxParallelTasks: Int = 1,
        systemPrompt: String? = nil,
        kickMethod: KickMethod = .cli,
        kickCommand: String? = nil,
        authLevel: AuthLevel = .level0,
        passkey: String? = nil
    ) throws -> Agent {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Name cannot be empty")
        }

        let agent = Agent(
            id: AgentID.generate(),
            name: name,
            role: role,
            type: type,
            aiType: aiType,
            hierarchyType: hierarchyType,
            roleType: roleType,
            parentAgentId: parentAgentId,
            maxParallelTasks: maxParallelTasks,
            systemPrompt: systemPrompt,
            kickMethod: kickMethod,
            kickCommand: kickCommand,
            authLevel: authLevel,
            passkey: passkey
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
/// 要件: サブタスク概念は削除（タスク間の関係は依存関係のみ）
public struct GetTaskDetailUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let contextRepository: any ContextRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        contextRepository: any ContextRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.contextRepository = contextRepository
    }

    public struct Result: Sendable {
        public let task: Task
        public let contexts: [Context]
        public let dependentTasks: [Task]
    }

    public func execute(taskId: TaskID) throws -> Result {
        guard let task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let contexts = try contextRepository.findByTask(taskId)

        // 依存タスクを取得
        var dependentTasks: [Task] = []
        for depId in task.dependencies {
            if let depTask = try taskRepository.findById(depId) {
                dependentTasks.append(depTask)
            }
        }

        return Result(task: task, contexts: contexts, dependentTasks: dependentTasks)
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
