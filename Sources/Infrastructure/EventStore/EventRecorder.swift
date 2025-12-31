// Sources/Infrastructure/EventStore/EventRecorder.swift
// 参照: docs/prd/STATE_HISTORY.md - イベントソーシング

import Foundation
import GRDB
import Domain

/// イベント記録サービス
/// 状態変更を自動的にイベントとして記録する
public final class EventRecorder: Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    // MARK: - Task Events

    /// タスクステータス変更を記録
    public func recordTaskStatusChange(
        task: Task,
        previousStatus: TaskStatus,
        agentId: AgentID?,
        sessionId: SessionID?,
        reason: String? = nil
    ) throws {
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
        try save(event)
    }

    /// タスク割り当て変更を記録
    public func recordTaskAssignment(
        task: Task,
        previousAssignee: AgentID?,
        agentId: AgentID?,
        sessionId: SessionID?
    ) throws {
        let eventType: EventType = task.assigneeId != nil ? .assigned : .unassigned
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: eventType,
            agentId: agentId,
            sessionId: sessionId,
            previousState: previousAssignee?.value,
            newState: task.assigneeId?.value
        )
        try save(event)
    }

    /// タスク作成を記録
    public func recordTaskCreated(
        task: Task,
        agentId: AgentID?,
        sessionId: SessionID?
    ) throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: task.projectId,
            entityType: .task,
            entityId: task.id.value,
            eventType: .created,
            agentId: agentId,
            sessionId: sessionId,
            newState: task.status.rawValue
        )
        try save(event)
    }

    // MARK: - Session Events

    /// セッション開始を記録
    public func recordSessionStarted(
        session: Session
    ) throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: session.projectId,
            entityType: .session,
            entityId: session.id.value,
            eventType: .started,
            agentId: session.agentId,
            sessionId: session.id,
            newState: session.status.rawValue
        )
        try save(event)
    }

    /// セッション終了を記録
    public func recordSessionEnded(
        session: Session,
        previousStatus: SessionStatus
    ) throws {
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
        try save(event)
    }

    // MARK: - Handoff Events

    /// ハンドオフ作成を記録
    public func recordHandoffCreated(
        handoff: Handoff,
        projectId: ProjectID
    ) throws {
        var metadata: [String: String] = [:]
        if let toAgent = handoff.toAgentId {
            metadata["to_agent_id"] = toAgent.value
        }

        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .created,
            agentId: handoff.fromAgentId,
            metadata: metadata.isEmpty ? nil : metadata
        )
        try save(event)
    }

    /// ハンドオフ承認を記録
    public func recordHandoffAccepted(
        handoff: Handoff,
        projectId: ProjectID,
        acceptingAgentId: AgentID
    ) throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .handoff,
            entityId: handoff.id.value,
            eventType: .completed,
            agentId: acceptingAgentId,
            previousState: "pending",
            newState: "accepted"
        )
        try save(event)
    }

    // MARK: - Context Events

    /// コンテキスト保存を記録
    public func recordContextSaved(
        context: Context,
        projectId: ProjectID
    ) throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: .context,
            entityId: context.id.value,
            eventType: .created,
            agentId: context.agentId,
            sessionId: context.sessionId
        )
        try save(event)
    }

    // MARK: - Generic Events

    /// 汎用イベントを記録
    public func recordEvent(
        projectId: ProjectID,
        entityType: EntityType,
        entityId: String,
        eventType: EventType,
        agentId: AgentID? = nil,
        sessionId: SessionID? = nil,
        previousState: String? = nil,
        newState: String? = nil,
        reason: String? = nil,
        metadata: [String: String]? = nil
    ) throws {
        let event = StateChangeEvent(
            id: EventID.generate(),
            projectId: projectId,
            entityType: entityType,
            entityId: entityId,
            eventType: eventType,
            agentId: agentId,
            sessionId: sessionId,
            previousState: previousState,
            newState: newState,
            reason: reason,
            metadata: metadata
        )
        try save(event)
    }

    // MARK: - Private

    private func save(_ event: StateChangeEvent) throws {
        try db.write { db in
            try EventRecord.fromDomain(event).insert(db)
        }
    }
}
