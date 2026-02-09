// Sources/UseCase/Audit/AuditLockUseCases.swift
// Audit Lock/Unlock系ユースケース
// 参照: docs/requirements/AUDIT.md - ロック機能

import Foundation
import Domain

// MARK: - LockTaskUseCase

/// タスクロックユースケース
/// 参照: docs/requirements/AUDIT.md - ロック機能
public struct LockTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(taskId: TaskID, auditId: InternalAuditID) throws -> Task {
        // Audit存在確認
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        // Auditがアクティブかどうか確認
        guard audit.status == .active else {
            throw UseCaseError.validationFailed("Only active audits can lock tasks")
        }

        // タスク取得
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 既にロック済みの場合はエラー
        guard !task.isLocked else {
            throw UseCaseError.validationFailed("Task is already locked")
        }

        // ロック実行
        task.isLocked = true
        task.lockedByAuditId = auditId
        task.lockedAt = Date()
        task.updatedAt = Date()

        try taskRepository.save(task)
        return task
    }
}

// MARK: - UnlockTaskUseCase

/// タスクロック解除ユースケース
/// 参照: docs/requirements/AUDIT.md - ロック解除（監査エージェントのみ解除可能）
public struct UnlockTaskUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.internalAuditRepository = internalAuditRepository
    }

    /// ロック解除（ロックをかけた監査のみ解除可能）
    public func execute(taskId: TaskID, auditId: InternalAuditID) throws -> Task {
        // タスク取得
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // ロックされていない場合はエラー
        guard task.isLocked else {
            throw UseCaseError.validationFailed("Task is not locked")
        }

        // ロックをかけた監査のみ解除可能
        guard task.lockedByAuditId == auditId else {
            throw UseCaseError.validationFailed("Only the audit that locked the task can unlock it")
        }

        // ロック解除
        task.isLocked = false
        task.lockedByAuditId = nil
        task.lockedAt = nil
        task.updatedAt = Date()

        try taskRepository.save(task)
        return task
    }
}

// MARK: - LockAgentUseCase

/// エージェントロックユースケース
/// 参照: docs/requirements/AUDIT.md - ロック機能
public struct LockAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        agentRepository: any AgentRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.agentRepository = agentRepository
        self.internalAuditRepository = internalAuditRepository
    }

    public func execute(agentId: AgentID, auditId: InternalAuditID) throws -> Agent {
        // Audit存在確認
        guard let audit = try internalAuditRepository.findById(auditId) else {
            throw UseCaseError.internalAuditNotFound(auditId)
        }

        // Auditがアクティブかどうか確認
        guard audit.status == .active else {
            throw UseCaseError.validationFailed("Only active audits can lock agents")
        }

        // エージェント取得
        guard var agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // 既にロック済みの場合はエラー
        guard !agent.isLocked else {
            throw UseCaseError.validationFailed("Agent is already locked")
        }

        // ロック実行
        agent.isLocked = true
        agent.lockedByAuditId = auditId
        agent.lockedAt = Date()
        agent.updatedAt = Date()

        try agentRepository.save(agent)
        return agent
    }
}

// MARK: - UnlockAgentUseCase

/// エージェントロック解除ユースケース
/// 参照: docs/requirements/AUDIT.md - ロック解除（監査エージェントのみ解除可能）
public struct UnlockAgentUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol
    private let internalAuditRepository: any InternalAuditRepositoryProtocol

    public init(
        agentRepository: any AgentRepositoryProtocol,
        internalAuditRepository: any InternalAuditRepositoryProtocol
    ) {
        self.agentRepository = agentRepository
        self.internalAuditRepository = internalAuditRepository
    }

    /// ロック解除（ロックをかけた監査のみ解除可能）
    public func execute(agentId: AgentID, auditId: InternalAuditID) throws -> Agent {
        // エージェント取得
        guard var agent = try agentRepository.findById(agentId) else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // ロックされていない場合はエラー
        guard agent.isLocked else {
            throw UseCaseError.validationFailed("Agent is not locked")
        }

        // ロックをかけた監査のみ解除可能
        guard agent.lockedByAuditId == auditId else {
            throw UseCaseError.validationFailed("Only the audit that locked the agent can unlock it")
        }

        // ロック解除
        agent.isLocked = false
        agent.lockedByAuditId = nil
        agent.lockedAt = nil
        agent.updatedAt = Date()

        try agentRepository.save(agent)
        return agent
    }
}

// MARK: - GetLockedTasksUseCase

/// ロック中のタスク一覧取得ユースケース
public struct GetLockedTasksUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol

    public init(taskRepository: any TaskRepositoryProtocol) {
        self.taskRepository = taskRepository
    }

    public func execute(auditId: InternalAuditID? = nil) throws -> [Task] {
        try taskRepository.findLocked(byAuditId: auditId)
    }
}

// MARK: - GetLockedAgentsUseCase

/// ロック中のエージェント一覧取得ユースケース
public struct GetLockedAgentsUseCase: Sendable {
    private let agentRepository: any AgentRepositoryProtocol

    public init(agentRepository: any AgentRepositoryProtocol) {
        self.agentRepository = agentRepository
    }

    public func execute(auditId: InternalAuditID? = nil) throws -> [Agent] {
        try agentRepository.findLocked(byAuditId: auditId)
    }
}
