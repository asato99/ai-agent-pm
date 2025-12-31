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
