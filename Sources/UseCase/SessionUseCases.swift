// Sources/UseCase/SessionUseCases.swift
// セッション関連のユースケース

import Foundation
import Domain

// MARK: - StartSessionUseCase

/// セッション開始ユースケース
public struct StartSessionUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        sessionRepository: any SessionRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        projectId: ProjectID,
        agentId: AgentID
    ) throws -> Session {
        // エージェントの存在確認
        guard try agentRepository.findById(agentId) != nil else {
            throw UseCaseError.agentNotFound(agentId)
        }

        // 既存のアクティブセッションがないか確認
        if let existingSession = try sessionRepository.findActive(agentId: agentId) {
            throw UseCaseError.sessionAlreadyActive(existingSession.id)
        }

        let session = Session(
            id: SessionID.generate(),
            projectId: projectId,
            agentId: agentId,
            startedAt: Date(),
            status: .active
        )

        try sessionRepository.save(session)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .session,
            entityId: session.id.value,
            eventType: .started,
            agentId: agentId,
            sessionId: session.id,
            newState: session.status.rawValue
        )
        try eventRepository.save(event)

        return session
    }
}

// MARK: - EndSessionUseCase

/// セッション終了ユースケース
public struct EndSessionUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        sessionRepository: any SessionRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.sessionRepository = sessionRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        sessionId: SessionID,
        status: SessionStatus = .completed
    ) throws -> Session {
        guard var session = try sessionRepository.findById(sessionId) else {
            throw UseCaseError.sessionNotFound(sessionId)
        }

        guard session.status == .active else {
            throw UseCaseError.sessionNotActive
        }

        let previousStatus = session.status
        session.status = status
        session.endedAt = Date()

        try sessionRepository.save(session)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: session.projectId,
            entityType: .session,
            entityId: session.id.value,
            eventType: .completed,
            agentId: session.agentId,
            sessionId: session.id,
            previousState: previousStatus.rawValue,
            newState: session.status.rawValue
        )
        try eventRepository.save(event)

        return session
    }
}

// MARK: - GetActiveSessionUseCase

/// アクティブセッション取得ユースケース
public struct GetActiveSessionUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol

    public init(sessionRepository: any SessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    public func execute(agentId: AgentID) throws -> Session? {
        try sessionRepository.findActive(agentId: agentId)
    }
}


// MARK: - EndActiveSessionsUseCase

/// エージェントのアクティブセッションを全て終了するユースケース
/// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
public struct EndActiveSessionsUseCase: Sendable {
    private let sessionRepository: any SessionRepositoryProtocol

    public init(sessionRepository: any SessionRepositoryProtocol) {
        self.sessionRepository = sessionRepository
    }

    /// エージェント×プロジェクトのアクティブセッションを全て終了
    /// - Parameters:
    ///   - agentId: エージェントID
    ///   - projectId: プロジェクトID
    ///   - status: 終了ステータス（デフォルト: .completed）
    /// - Returns: 終了したセッション数
    public func execute(
        agentId: AgentID,
        projectId: ProjectID,
        status: SessionStatus = .completed
    ) throws -> Int {
        let activeSessions = try sessionRepository.findActiveByAgentAndProject(
            agentId: agentId,
            projectId: projectId
        )

        var endedCount = 0
        for var session in activeSessions {
            session.end(status: status)
            try sessionRepository.save(session)
            endedCount += 1
        }

        return endedCount
    }
}

// MARK: - CompleteTaskWithSessionCleanupUseCase

/// タスク完了結果
public enum TaskCompletionResult: String, Sendable {
    case success
    case failed
    case blocked
}

/// タスク完了とセッションクリーンアップの結果
public struct TaskCompletionWithCleanupResult: Sendable {
    public let task: Task
    public let endedSessionCount: Int

    public init(task: Task, endedSessionCount: Int) {
        self.task = task
        self.endedSessionCount = endedSessionCount
    }
}

/// タスク完了とセッションクリーンアップを同時に行うユースケース
/// 参照: docs/plan/PHASE4_COORDINATOR_ARCHITECTURE.md
public struct CompleteTaskWithSessionCleanupUseCase: Sendable {
    private let taskRepository: any TaskRepositoryProtocol
    private let sessionRepository: any SessionRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        taskRepository: any TaskRepositoryProtocol,
        sessionRepository: any SessionRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.taskRepository = taskRepository
        self.sessionRepository = sessionRepository
        self.eventRepository = eventRepository
    }

    /// タスクを完了し、関連するセッションをクリーンアップ
    /// - Parameters:
    ///   - taskId: タスクID
    ///   - agentId: エージェントID
    ///   - result: 完了結果（success/failed/blocked）
    /// - Returns: 完了したタスクと終了したセッション数
    public func execute(
        taskId: TaskID,
        agentId: AgentID,
        result: TaskCompletionResult
    ) throws -> TaskCompletionWithCleanupResult {
        // タスクを取得
        guard var task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        let previousStatus = task.status

        // 結果に応じてステータスを更新
        let newStatus: TaskStatus
        switch result {
        case .success:
            newStatus = .done
            task.completedAt = Date()
        case .failed, .blocked:
            newStatus = .blocked
        }

        task.status = newStatus
        task.updatedAt = Date()
        try taskRepository.save(task)

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: newStatus == .done ? .completed : .statusChanged,
            agentId: agentId,
            sessionId: nil,
            previousState: previousStatus.rawValue,
            newState: newStatus.rawValue
        )
        try eventRepository.save(event)

        // セッションをクリーンアップ
        let endSessionsUseCase = EndActiveSessionsUseCase(sessionRepository: sessionRepository)
        let sessionStatus: SessionStatus = (result == .success) ? .completed : .abandoned
        let endedCount = try endSessionsUseCase.execute(
            agentId: agentId,
            projectId: task.projectId,
            status: sessionStatus
        )

        return TaskCompletionWithCleanupResult(task: task, endedSessionCount: endedCount)
    }
}
