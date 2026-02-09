// Sources/UseCase/Task/TaskQueries.swift
// タスク読み取り系ユースケース

import Foundation
import Domain

// MARK: - GetTasksUseCase

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

// MARK: - GetTasksByAssigneeUseCase

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

// MARK: - GetTaskDetailUseCase

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

// MARK: - GetPendingTasksUseCase

/// Phase 3-2: 作業中タスク取得ユースケース
/// 外部Runnerが作業継続のため現在進行中のタスクを取得
/// 参照: docs/plan/PHASE3_PULL_ARCHITECTURE.md
public struct GetPendingTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(agentId: AgentID) throws -> [Task] {
        try taskRepository.findPendingByAssignee(agentId)
    }
}
