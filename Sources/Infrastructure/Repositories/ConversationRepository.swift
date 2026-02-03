// Sources/Infrastructure/Repositories/ConversationRepository.swift
// 参照: docs/design/AI_TO_AI_CONVERSATION.md

import Foundation
import GRDB
import Domain

// MARK: - ConversationRecord

/// GRDB用のConversationレコード
struct ConversationRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "conversations"

    var id: String
    var projectId: String
    /// 紐付くタスクID（ChatDelegation から継承）
    var taskId: String?
    var initiatorAgentId: String
    var participantAgentId: String
    var state: String
    var purpose: String?
    var maxTurns: Int
    var createdAt: Date
    var endedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case projectId = "project_id"
        case taskId = "task_id"
        case initiatorAgentId = "initiator_agent_id"
        case participantAgentId = "participant_agent_id"
        case state
        case purpose
        case maxTurns = "max_turns"
        case createdAt = "created_at"
        case endedAt = "ended_at"
    }

    func toDomain() -> Conversation {
        Conversation(
            id: ConversationID(value: id),
            projectId: ProjectID(value: projectId),
            taskId: taskId.map { TaskID(value: $0) },
            initiatorAgentId: AgentID(value: initiatorAgentId),
            participantAgentId: AgentID(value: participantAgentId),
            state: ConversationState(rawValue: state) ?? .pending,
            purpose: purpose,
            maxTurns: maxTurns,
            createdAt: createdAt,
            endedAt: endedAt
        )
    }

    static func fromDomain(_ entity: Conversation) -> ConversationRecord {
        ConversationRecord(
            id: entity.id.value,
            projectId: entity.projectId.value,
            taskId: entity.taskId?.value,
            initiatorAgentId: entity.initiatorAgentId.value,
            participantAgentId: entity.participantAgentId.value,
            state: entity.state.rawValue,
            purpose: entity.purpose,
            maxTurns: entity.maxTurns,
            createdAt: entity.createdAt,
            endedAt: entity.endedAt
        )
    }
}

// MARK: - ConversationRepository

/// AI-to-AI会話リポジトリ
public final class ConversationRepository: ConversationRepositoryProtocol, Sendable {
    private let db: DatabaseQueue

    public init(database: DatabaseQueue) {
        self.db = database
    }

    public func save(_ conversation: Conversation) throws {
        try db.write { db in
            try ConversationRecord.fromDomain(conversation)
                .save(db, onConflict: .replace)
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func findById(_ id: ConversationID) throws -> Conversation? {
        try db.read { db in
            try ConversationRecord
                .filter(Column("id") == id.value)
                .fetchOne(db)?
                .toDomain()
        }
    }

    public func findActiveByAgentId(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] {
        try db.read { db in
            try ConversationRecord
                .filter(Column("project_id") == projectId.value)
                .filter(
                    Column("initiator_agent_id") == agentId.value ||
                    Column("participant_agent_id") == agentId.value
                )
                // active または terminating 状態の会話を検索
                .filter(
                    Column("state") == ConversationState.active.rawValue ||
                    Column("state") == ConversationState.terminating.rawValue
                )
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func findPendingForParticipant(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] {
        try db.read { db in
            try ConversationRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("participant_agent_id") == agentId.value)
                .filter(Column("state") == ConversationState.pending.rawValue)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    /// イニシエーターのpending会話を検索
    /// 参照: docs/design/AI_TO_AI_CONVERSATION.md - pending状態でもイニシエーターからのメッセージは許可
    public func findPendingForInitiator(_ agentId: AgentID, projectId: ProjectID) throws -> [Conversation] {
        try db.read { db in
            try ConversationRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("initiator_agent_id") == agentId.value)
                .filter(Column("state") == ConversationState.pending.rawValue)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }

    public func updateState(_ id: ConversationID, state: ConversationState) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE conversations
                    SET state = ?
                    WHERE id = ?
                """,
                arguments: [state.rawValue, id.value]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func updateState(_ id: ConversationID, state: ConversationState, endedAt: Date?) throws {
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE conversations
                    SET state = ?, ended_at = ?
                    WHERE id = ?
                """,
                arguments: [state.rawValue, endedAt, id.value]
            )
        }

        // WAL mode: 他プロセスからの可視性を確保
        try? db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(PASSIVE)")
        }
    }

    public func updateLastActivity(_ id: ConversationID, at date: Date) throws {
        // Note: 現在のスキーマにはlast_activity_atがないため、このメソッドは将来の拡張用
        // 現時点ではno-opとして実装
    }

    public func hasActiveOrPendingConversation(
        initiatorAgentId: AgentID,
        participantAgentId: AgentID,
        projectId: ProjectID
    ) throws -> Bool {
        try db.read { db in
            let count = try ConversationRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("initiator_agent_id") == initiatorAgentId.value)
                .filter(Column("participant_agent_id") == participantAgentId.value)
                .filter(
                    Column("state") == ConversationState.active.rawValue ||
                    Column("state") == ConversationState.pending.rawValue
                )
                .fetchCount(db)
            return count > 0
        }
    }

    /// タスクIDに紐付く会話を検索
    /// get_task_conversations ツールで使用
    /// 参照: docs/design/TASK_CONVERSATION_AWAIT.md
    public func findByTaskId(_ taskId: TaskID, projectId: ProjectID) throws -> [Conversation] {
        try db.read { db in
            try ConversationRecord
                .filter(Column("project_id") == projectId.value)
                .filter(Column("task_id") == taskId.value)
                .order(Column("created_at").desc)
                .fetchAll(db)
                .map { $0.toDomain() }
        }
    }
}
