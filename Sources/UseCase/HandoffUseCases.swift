// Sources/UseCase/HandoffUseCases.swift
// ハンドオフ関連のユースケース

import Foundation
import Domain

// MARK: - CreateHandoffUseCase

/// ハンドオフ作成ユースケース
public struct CreateHandoffUseCase: Sendable {
    private let handoffRepository: any HandoffRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let agentRepository: any AgentRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        handoffRepository: any HandoffRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        agentRepository: any AgentRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.handoffRepository = handoffRepository
        self.taskRepository = taskRepository
        self.agentRepository = agentRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        taskId: TaskID,
        fromAgentId: AgentID,
        toAgentId: AgentID?,
        summary: String,
        context: String? = nil,
        recommendations: String? = nil
    ) throws -> Handoff {
        // タスクの存在確認
        guard let task = try taskRepository.findById(taskId) else {
            throw UseCaseError.taskNotFound(taskId)
        }

        // 送信元エージェントの存在確認
        guard try agentRepository.findById(fromAgentId) != nil else {
            throw UseCaseError.agentNotFound(fromAgentId)
        }

        // 送信先エージェントの存在確認（指定されている場合）
        if let toAgentId = toAgentId {
            guard try agentRepository.findById(toAgentId) != nil else {
                throw UseCaseError.agentNotFound(toAgentId)
            }
        }

        // バリデーション
        guard !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw UseCaseError.validationFailed("Summary cannot be empty")
        }

        let handoff = Handoff(
            id: HandoffID.generate(),
            taskId: taskId,
            fromAgentId: fromAgentId,
            toAgentId: toAgentId,
            summary: summary,
            context: context,
            recommendations: recommendations
        )

        try handoffRepository.save(handoff)

        // イベント記録
        var metadata: [String: String] = [:]
        if let toAgent = toAgentId {
            metadata["to_agent_id"] = toAgent.value
        }

        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .created,
            agentId: fromAgentId,
            metadata: metadata.isEmpty ? nil : metadata
        )
        try eventRepository.save(event)

        return handoff
    }
}

// MARK: - AcceptHandoffUseCase

/// ハンドオフ承認ユースケース
public struct AcceptHandoffUseCase: Sendable {
    private let handoffRepository: any HandoffRepositoryProtocol
    private let taskRepository: any TaskRepositoryProtocol
    private let eventRepository: any EventRepositoryProtocol

    public init(
        handoffRepository: any HandoffRepositoryProtocol,
        taskRepository: any TaskRepositoryProtocol,
        eventRepository: any EventRepositoryProtocol
    ) {
        self.handoffRepository = handoffRepository
        self.taskRepository = taskRepository
        self.eventRepository = eventRepository
    }

    public func execute(
        handoffId: HandoffID,
        acceptingAgentId: AgentID
    ) throws -> Handoff {
        guard var handoff = try handoffRepository.findById(handoffId) else {
            throw UseCaseError.validationFailed("Handoff not found")
        }

        // 既に承認済みでないか確認
        guard handoff.acceptedAt == nil else {
            throw UseCaseError.validationFailed("Handoff already accepted")
        }

        // 対象エージェントの確認（指定されている場合）
        if let targetAgentId = handoff.toAgentId {
            guard targetAgentId == acceptingAgentId else {
                throw UseCaseError.unauthorized
            }
        }

        handoff.acceptedAt = Date()

        try handoffRepository.save(handoff)

        // タスクのプロジェクトIDを取得
        guard let task = try taskRepository.findById(handoff.taskId) else {
            throw UseCaseError.taskNotFound(handoff.taskId)
        }

        // イベント記録
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .completed,
            agentId: acceptingAgentId,
            previousState: "pending",
            newState: "accepted"
        )
        try eventRepository.save(event)

        return handoff
    }
}

// MARK: - GetPendingHandoffsUseCase

/// 未処理ハンドオフ取得ユースケース
public struct GetPendingHandoffsUseCase: Sendable {
    private let handoffRepository: any HandoffRepositoryProtocol

    public init(handoffRepository: any HandoffRepositoryProtocol) {
        self.handoffRepository = handoffRepository
    }

    /// 指定エージェント宛ての未処理ハンドオフを取得
    /// agentIdがnilの場合は全ての未処理ハンドオフを取得
    public func execute(agentId: AgentID?) throws -> [Handoff] {
        try handoffRepository.findPending(agentId: agentId)
    }
}
