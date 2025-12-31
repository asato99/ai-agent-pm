// Sources/UseCase/ContextUseCases.swift
// コンテキスト関連のユースケース

import Foundation
import Domain

// MARK: - SaveContextUseCase

/// コンテキスト保存ユースケース
public struct SaveContextUseCase: Sendable {
    private let contextRepository: any ContextRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let sessionRepository: any SessionRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        contextRepository: any ContextRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        sessionRepository: any SessionRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.contextRepository = contextRepository
        self.taskRepository = taskRepository
        self.sessionRepository = sessionRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        sessionId: SessionID,
        agentId: AgentID,
        progress: String? = nil,
        findings: String? = nil,
        blockers: String? = nil,
        nextSteps: String? = nil
    ) throws -> Context {
        // タスクの存在確認
        guard let task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // セッションの存在確認とアクティブ状態確認
        guard let session = try sessionRepository.findById(sessionId) else {
            throw UseCaseError.sessionNotFound(sessionId)
        }

        guard session.status == .active else {
            throw UseCaseError.sessionNotActive
        }

        let context = Context(
            id: ContextID.generate(),
            taskId: taskId,
            sessionId: sessionId,
            agentId: agentId,
            progress: progress,
            findings: findings,
            blockers: blockers,
            nextSteps: nextSteps
        )

        try contextRepository.save(context)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .context,
            entityId: context.id.value,
            eventType: .created,
            agentId: agentId,
            sessionId: sessionId
        )
        try eventRepository.save(event)

        return context
    }
}

// MARK: - GetTaskContextUseCase

/// タスクコンテキスト取得ユースケース
public struct GetTaskContextUseCase: Sendable {
    private let contextRepository: any ContextRepositoryProtocol

    public init(contextRepository: any ContextRepositoryProtocol) {
        self.contextRepository = contextRepository
    }

    /// タスクの最新コンテキストを取得
    public func executeLatest(taskId: TaskID) throws -> Context? {
        try contextRepository.findLatest(taskId: taskId)
    }

    /// タスクの全コンテキスト履歴を取得
    public func executeAll(taskId: TaskID) throws -> [Context] {
        try contextRepository.findByTask(taskId)
    }
}
